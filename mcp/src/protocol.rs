use serde::{Deserialize, Serialize};
use serde_json::Value;

/// MCP protocol version we advertise.
pub const MCP_PROTOCOL_VERSION: &str = "2024-11-05";

/// JSON-RPC request envelope.
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct JsonRpcRequest {
    pub jsonrpc: String,
    #[serde(default)]
    pub id: Option<Value>,
    pub method: String,
    #[serde(default)]
    pub params: Option<Value>,
}

/// JSON-RPC response envelope.
#[derive(Debug, Serialize)]
pub struct JsonRpcResponse {
    pub jsonrpc: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<JsonRpcError>,
}

impl JsonRpcResponse {
    pub fn success(id: Option<Value>, result: Value) -> Self {
        Self {
            jsonrpc: "2.0",
            id,
            result: Some(result),
            error: None,
        }
    }

    pub fn error(id: Option<Value>, code: i32, message: String, data: Option<Value>) -> Self {
        Self {
            jsonrpc: "2.0",
            id,
            result: None,
            error: Some(JsonRpcError {
                code,
                message,
                data,
            }),
        }
    }
}

#[derive(Debug, Serialize)]
pub struct JsonRpcError {
    pub code: i32,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

/// Standard JSON-RPC error codes.
pub mod error_code {
    pub const PARSE_ERROR: i32 = -32700;
    pub const METHOD_NOT_FOUND: i32 = -32601;
    pub const INVALID_PARAMS: i32 = -32602;
    pub const INTERNAL_ERROR: i32 = -32603;
    /// Request was cancelled via `notifications/cancelled` (LSP-style extension).
    pub const REQUEST_CANCELLED: i32 = -32800;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn request_cancelled_code_is_neg32800() {
        assert_eq!(error_code::REQUEST_CANCELLED, -32800);
    }

    #[test]
    fn cancelled_response_carries_request_cancelled_code() {
        let resp = JsonRpcResponse::error(
            Some(serde_json::json!(5)),
            error_code::REQUEST_CANCELLED,
            "request cancelled".to_string(),
            None,
        );
        let err = resp.error.expect("error field set");
        assert_eq!(err.code, -32800);
        assert_eq!(resp.id, Some(serde_json::json!(5)));
    }

    #[test]
    fn call_tool_error_result_sets_is_error() {
        let r = CallToolResult::error("boom".to_string());
        let v = serde_json::to_value(&r).unwrap();
        assert_eq!(v["is_error"], true);
        assert_eq!(v["content"][0]["type"], "text");
        assert_eq!(v["content"][0]["text"], "boom");
    }

    #[test]
    fn success_response_omits_error_field() {
        let resp =
            JsonRpcResponse::success(Some(serde_json::json!(1)), serde_json::json!({"ok": true}));
        let s = serde_json::to_string(&resp).unwrap();
        assert!(!s.contains("error"), "error field leaked into success: {}", s);
        assert!(s.contains("\"result\""));
    }

    #[test]
    fn error_response_omits_result_field() {
        let resp = JsonRpcResponse::error(
            Some(serde_json::json!(2)),
            error_code::METHOD_NOT_FOUND,
            "nope".to_string(),
            None,
        );
        let s = serde_json::to_string(&resp).unwrap();
        assert!(!s.contains("\"result\""));
        assert!(s.contains("\"error\""));
        assert!(s.contains("-32601"));
    }
}

/// initialize request params.
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct InitializeParams {
    #[serde(default)]
    pub protocol_version: Option<String>,
    #[serde(default)]
    pub capabilities: Option<Value>,
    #[serde(default)]
    pub client_info: Option<Implementation>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Implementation {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
}

/// initialize response result.
#[derive(Debug, Serialize)]
pub struct InitializeResult {
    pub protocol_version: &'static str,
    pub capabilities: ServerCapabilities,
    pub server_info: Implementation,
}

#[derive(Debug, Serialize)]
pub struct ServerCapabilities {
    pub tools: ToolsCapability,
}

#[derive(Debug, Serialize)]
pub struct ToolsCapability {
    pub list_changed: bool,
}

/// Tool definition for tools/list.
#[derive(Debug, Serialize)]
pub struct Tool {
    pub name: &'static str,
    pub description: &'static str,
    pub input_schema: Value,
}

/// tools/call request params.
#[derive(Debug, Deserialize)]
pub struct CallToolParams {
    pub name: String,
    #[serde(default)]
    pub arguments: Option<Value>,
}

/// tools/call response result.
#[derive(Debug, Serialize)]
pub struct CallToolResult {
    pub content: Vec<ToolContent>,
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub is_error: bool,
}

impl CallToolResult {
    pub fn text(text: String) -> Self {
        Self {
            content: vec![ToolContent::text(text)],
            is_error: false,
        }
    }

    pub fn error(text: String) -> Self {
        Self {
            content: vec![ToolContent::text(text)],
            is_error: true,
        }
    }
}

#[derive(Debug, Serialize)]
pub struct ToolContent {
    #[serde(rename = "type")]
    pub kind: &'static str,
    pub text: String,
}

impl ToolContent {
    pub fn text(text: String) -> Self {
        Self { kind: "text", text }
    }
}

/// Build a JSON Schema object property descriptor.
pub fn prop(description: &'static str, ty: &'static str) -> Value {
    serde_json::json!({
        "type": ty,
        "description": description
    })
}

pub fn string_prop(description: &'static str) -> Value {
    prop(description, "string")
}

pub fn integer_prop(description: &'static str) -> Value {
    prop(description, "integer")
}

pub fn boolean_prop(description: &'static str) -> Value {
    prop(description, "boolean")
}
