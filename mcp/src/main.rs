mod client;
mod protocol;
mod tools;
mod utils;

use client::LanluApiClient;
use protocol::{
    error_code, CallToolParams, Implementation, InitializeParams, InitializeResult, JsonRpcRequest,
    JsonRpcResponse, ServerCapabilities, ToolsCapability, MCP_PROTOCOL_VERSION,
};
use serde_json::Value;
use std::collections::HashMap;
use std::io::{self, Write};
use std::process;
use std::sync::{Arc, Mutex};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::sync::{mpsc, oneshot};

/// In-flight request id -> cancellation sender. When a `notifications/cancelled`
/// arrives we pull the matching sender and fire it; the handler task's
/// `select!` then resolves with a cancelled response instead of waiting for
/// the (possibly long-running) tool call to finish.
type CancelMap = Arc<Mutex<HashMap<Value, oneshot::Sender<()>>>>;

#[tokio::main]
async fn main() {
    let token = match std::env::var("LANLU_TOKEN") {
        Ok(t) if !t.is_empty() => t,
        _ => {
            eprintln!("LANLU_TOKEN environment variable is required");
            process::exit(1);
        }
    };
    if let Err(e) = client::validate_token(&token) {
        eprintln!("{}", e);
        process::exit(1);
    }

    let host = std::env::var("LANLU_HOST").unwrap_or_else(|_| "http://localhost:8082".to_string());
    let no_proxy = std::env::var("LANLU_NO_PROXY").is_ok();
    let client = Arc::new(LanluApiClient::new(host, token, no_proxy));

    // All stdout writes go through a single writer task so concurrent tool
    // handlers can never interleave lines on the wire.
    let (tx, rx) = mpsc::unbounded_channel::<JsonRpcResponse>();
    tokio::spawn(writer_task(rx));

    let cancel_map: CancelMap = Arc::new(Mutex::new(HashMap::new()));

    let stdin = tokio::io::stdin();
    let mut reader = BufReader::new(stdin);
    let mut line_buf = String::new();

    loop {
        line_buf.clear();
        match reader.read_line(&mut line_buf).await {
            Ok(0) => break, // EOF: client closed stdin
            Ok(_) => {}
            Err(e) => {
                let _ = tx.send(JsonRpcResponse::error(
                    None,
                    error_code::PARSE_ERROR,
                    format!("failed to read line: {}", e),
                    None,
                ));
                continue;
            }
        }
        let line = line_buf.trim_end_matches(['\r', '\n']);

        let request: JsonRpcRequest = match serde_json::from_str(line) {
            Ok(r) => r,
            Err(e) => {
                let _ = tx.send(JsonRpcResponse::error(
                    None,
                    error_code::PARSE_ERROR,
                    format!("invalid JSON: {}", e),
                    None,
                ));
                continue;
            }
        };

        // Cancellation notifications are handled inline (not spawned) so they
        // can interrupt an in-flight tools/call without queueing behind it.
        if request.method == "notifications/cancelled" {
            if let Some(request_id) = request
                .params
                .as_ref()
                .and_then(|p| p.get("requestId"))
                .cloned()
            {
                if let Some(sender) = cancel_map.lock().unwrap().remove(&request_id) {
                    let _ = sender.send(());
                }
            }
            continue;
        }

        // Other notifications (e.g. `initialized`) carry no id and expect no
        // response, so there is nothing to do.
        if request.id.is_none() {
            continue;
        }

        // Requests with an id are handled on their own task so the reader loop
        // keeps draining stdin (and can act on later cancellation signals)
        // while a slow tool call runs.
        // id is present here: id-less notifications were skipped above.
        let id = request.id.clone().unwrap();
        let (cancel_tx, cancel_rx) = oneshot::channel();
        cancel_map.lock().unwrap().insert(id.clone(), cancel_tx);

        let client = client.clone();
        let cancel_map = cancel_map.clone();
        let tx = tx.clone();
        tokio::spawn(async move {
            let response = tokio::select! {
                resp = handle_request(&client, request) => resp,
                _ = cancel_rx => Some(JsonRpcResponse::error(
                    Some(id.clone()),
                    error_code::REQUEST_CANCELLED,
                    "request cancelled".to_string(),
                    None,
                )),
            };
            // Best-effort cleanup: the entry may already have been removed by
            // the cancellation handler.
            cancel_map.lock().unwrap().remove(&id);
            if let Some(resp) = response {
                let _ = tx.send(resp);
            }
        });
    }
    // stdin closed: dropping our sender lets the writer task drain any final
    // responses and exit; remaining in-flight tasks are aborted at runtime
    // shutdown.
    drop(tx);
}

/// Single owner of stdout. Serializes every JSON-RPC line so concurrent
/// handler tasks can't interleave output.
async fn writer_task(mut rx: mpsc::UnboundedReceiver<JsonRpcResponse>) {
    let mut stdout = io::stdout();
    while let Some(response) = rx.recv().await {
        let line = match serde_json::to_string(&response) {
            Ok(s) => s,
            Err(e) => {
                let fallback = JsonRpcResponse::error(
                    response.id,
                    error_code::INTERNAL_ERROR,
                    format!("failed to serialize response: {}", e),
                    None,
                );
                serde_json::to_string(&fallback).unwrap_or_else(|_| {
                    format!(
                        "{{\"jsonrpc\":\"2.0\",\"error\":{{\"code\":{},\"message\":\"serialization failure\"}}}}",
                        error_code::INTERNAL_ERROR
                    )
                })
            }
        };
        let _ = writeln!(stdout, "{}", line);
        let _ = stdout.flush();
    }
}

async fn handle_request(
    client: &LanluApiClient,
    request: JsonRpcRequest,
) -> Option<JsonRpcResponse> {
    let id = request.id.clone();

    match request.method.as_str() {
        "initialize" => Some(handle_initialize(id, request.params)),
        "tools/list" => Some(handle_tools_list(id)),
        "tools/call" => Some(handle_tools_call(client, id, request.params).await),
        _ => Some(JsonRpcResponse::error(
            id,
            error_code::METHOD_NOT_FOUND,
            format!("method not found: {}", request.method),
            None,
        )),
    }
}

fn handle_initialize(id: Option<Value>, params: Option<Value>) -> JsonRpcResponse {
    let _params: Option<InitializeParams> = params.and_then(|p| serde_json::from_value(p).ok());

    let result = InitializeResult {
        protocol_version: MCP_PROTOCOL_VERSION,
        capabilities: ServerCapabilities {
            tools: ToolsCapability {
                list_changed: false,
            },
        },
        server_info: Implementation {
            name: "lanlu-mcp".to_string(),
            version: Some(env!("CARGO_PKG_VERSION").to_string()),
        },
    };

    match serde_json::to_value(result) {
        Ok(v) => JsonRpcResponse::success(id, v),
        Err(e) => JsonRpcResponse::error(
            id,
            error_code::INTERNAL_ERROR,
            format!("serialize initialize result failed: {}", e),
            None,
        ),
    }
}

fn handle_tools_list(id: Option<Value>) -> JsonRpcResponse {
    let tools = tools::all_tools();
    let result = serde_json::json!({ "tools": tools });
    JsonRpcResponse::success(id, result)
}

async fn handle_tools_call(
    client: &LanluApiClient,
    id: Option<Value>,
    params: Option<Value>,
) -> JsonRpcResponse {
    let params: CallToolParams = match params {
        Some(p) => match serde_json::from_value(p) {
            Ok(v) => v,
            Err(e) => {
                return JsonRpcResponse::error(
                    id,
                    error_code::INVALID_PARAMS,
                    format!("invalid tools/call params: {}", e),
                    None,
                )
            }
        },
        None => {
            return JsonRpcResponse::error(
                id,
                error_code::INVALID_PARAMS,
                "missing tools/call params".to_string(),
                None,
            )
        }
    };

    let result = tools::dispatch(client, &params.name, &params).await;
    match serde_json::to_value(result) {
        Ok(v) => JsonRpcResponse::success(id, v),
        Err(e) => JsonRpcResponse::error(
            id,
            error_code::INTERNAL_ERROR,
            format!("serialize tool result failed: {}", e),
            None,
        ),
    }
}
