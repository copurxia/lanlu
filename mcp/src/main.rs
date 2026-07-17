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
use std::io::{self, BufRead, Write};
use std::process;

#[tokio::main]
async fn main() {
    let token = match std::env::var("LANLU_TOKEN") {
        Ok(t) if !t.is_empty() => t,
        _ => {
            eprintln!("LANLU_TOKEN environment variable is required");
            process::exit(1);
        }
    };

    let host = std::env::var("LANLU_HOST").unwrap_or_else(|_| "http://localhost:8082".to_string());
    let no_proxy = std::env::var("LANLU_NO_PROXY").is_ok();
    let client = LanluApiClient::new(host, token, no_proxy);

    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let reader = stdin.lock();

    for line in reader.lines() {
        let line = match line {
            Ok(l) => l,
            Err(e) => {
                write_response(
                    &mut stdout,
                    JsonRpcResponse::error(
                        None,
                        error_code::PARSE_ERROR,
                        format!("failed to read line: {}", e),
                        None,
                    ),
                );
                continue;
            }
        };

        let request: JsonRpcRequest = match serde_json::from_str(&line) {
            Ok(r) => r,
            Err(e) => {
                write_response(
                    &mut stdout,
                    JsonRpcResponse::error(
                        None,
                        error_code::PARSE_ERROR,
                        format!("invalid JSON: {}", e),
                        None,
                    ),
                );
                continue;
            }
        };

        let response = handle_request(&client, request).await;
        if let Some(resp) = response {
            write_response(&mut stdout, resp);
        }
    }
}

async fn handle_request(
    client: &LanluApiClient,
    request: JsonRpcRequest,
) -> Option<JsonRpcResponse> {
    let id = request.id.clone();

    match request.method.as_str() {
        "initialize" => Some(handle_initialize(id, request.params)),
        "initialized" => {
            // Notification, no response.
            None
        }
        "tools/list" => Some(handle_tools_list(id)),
        "tools/call" => Some(handle_tools_call(client, id, request.params).await),
        "notifications/cancelled" => {
            // Best-effort cancellation signal; not wired into task polling yet.
            None
        }
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

fn write_response(stdout: &mut io::Stdout, response: JsonRpcResponse) {
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
