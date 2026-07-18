use crate::client::LanluApiClient;
use crate::protocol::{CallToolParams, CallToolResult, Tool};
use serde_json::Value;

mod archive;
mod category;
mod cover;
mod download_upload;
mod info;
mod metadata;
mod search;
mod source;
mod tankoubon;
mod task;

/// Return the static list of all tools exposed by this MCP server.
pub fn all_tools() -> Vec<Tool> {
    vec![
        info::tool(),
        search::tool(),
        archive::tool(),
        category::tool(),
        cover::tool(),
        tankoubon::list_tool(),
        tankoubon::show_tool(),
        metadata::tool(),
        source::list_tool(),
        source::home_tool(),
        source::search_tool(),
        source::filters_tool(),
        source::download_tool(),
        download_upload::download_url_tool(),
        download_upload::upload_tool(),
        download_upload::metadata_run_tool(),
        task::tool(),
    ]
}

/// Dispatch a tools/call request to the appropriate handler.
pub async fn dispatch(
    client: &LanluApiClient,
    name: &str,
    params: &CallToolParams,
) -> CallToolResult {
    let args = params
        .arguments
        .as_ref()
        .cloned()
        .unwrap_or(Value::Object(serde_json::Map::new()));
    let result = match name {
        "lanlu_info" => info::run(client, &args).await,
        "lanlu_search" => search::run(client, &args).await,
        "lanlu_archive_show" => archive::run_show(client, &args).await,
        "lanlu_category_list" => category::run(client, &args).await,
        "lanlu_cover" => cover::run(client, &args).await,
        "lanlu_tankoubon_list" => tankoubon::run_list(client, &args).await,
        "lanlu_tankoubon_show" => tankoubon::run_show(client, &args).await,
        "lanlu_update_metadata" => metadata::run(client, &args).await,
        "lanlu_source_list" => source::run_list(client, &args).await,
        "lanlu_source_home" => source::run_home(client, &args).await,
        "lanlu_source_search" => source::run_search(client, &args).await,
        "lanlu_source_filters" => source::run_filters(client, &args).await,
        "lanlu_source_download" => source::run_download(client, &args).await,
        "lanlu_download_url" => download_upload::run_download_url(client, &args).await,
        "lanlu_upload" => download_upload::run_upload(client, &args).await,
        "lanlu_metadata_run" => download_upload::run_metadata_run(client, &args).await,
        "lanlu_task" => task::run(client, &args).await,
        _ => return CallToolResult::error(format!("unknown tool: {}", name)),
    };

    match result {
        Ok(text) => CallToolResult::text(text),
        Err(e) => CallToolResult::error(e),
    }
}

/// Helper: require a string field from arguments.
pub fn require_str(args: &Value, key: &str) -> Result<String, String> {
    args.get(key)
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| format!("missing required argument: {}", key))
}

/// Helper: optional string field from arguments.
pub fn optional_str(args: &Value, key: &str) -> Option<String> {
    args.get(key)
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
}

/// Helper: optional integer field from arguments.
pub fn optional_i64(args: &Value, key: &str) -> Option<i64> {
    args.get(key).and_then(|v| v.as_i64())
}

/// Helper: optional boolean field from arguments, default false.
pub fn optional_bool(args: &Value, key: &str) -> bool {
    args.get(key).and_then(|v| v.as_bool()).unwrap_or(false)
}

/// Helper: build a JSON object schema with listed properties.
pub fn object_schema(
    description: &'static str,
    required: &[&'static str],
    properties: Vec<(&'static str, Value)>,
) -> Value {
    let mut props = serde_json::Map::new();
    for (k, v) in properties {
        props.insert(k.to_string(), v);
    }
    serde_json::json!({
        "type": "object",
        "description": description,
        "required": required,
        "properties": props,
        "additionalProperties": false
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn require_str_returns_value_when_present() {
        let args = json!({"id": "abc"});
        assert_eq!(require_str(&args, "id").unwrap(), "abc");
    }

    #[test]
    fn require_str_errors_when_missing() {
        let args = json!({});
        assert!(require_str(&args, "id").is_err());
    }

    #[test]
    fn require_str_errors_when_not_a_string() {
        let args = json!({"id": 5});
        assert!(require_str(&args, "id").is_err());
    }

    #[test]
    fn optional_str_roundtrips() {
        assert_eq!(optional_str(&json!({}), "x"), None);
        assert_eq!(optional_str(&json!({"x": "y"}), "x"), Some("y".to_string()));
    }

    #[test]
    fn optional_i64_parses_integers_only() {
        assert_eq!(optional_i64(&json!({"n": 5}), "n"), Some(5));
        assert_eq!(optional_i64(&json!({"n": "5"}), "n"), None);
        assert_eq!(optional_i64(&json!({}), "n"), None);
    }

    #[test]
    fn optional_bool_defaults_false_and_only_accepts_bools() {
        assert_eq!(optional_bool(&json!({}), "b"), false);
        assert_eq!(optional_bool(&json!({"b": true}), "b"), true);
        assert_eq!(optional_bool(&json!({"b": false}), "b"), false);
        assert_eq!(optional_bool(&json!({"b": "true"}), "b"), false);
    }

    #[test]
    fn object_schema_is_strict_and_shaped() {
        let schema = object_schema(
            "desc",
            &["id"],
            vec![("id", serde_json::json!({"type": "string"}))],
        );
        assert_eq!(schema["type"], "object");
        assert_eq!(schema["description"], "desc");
        assert_eq!(schema["additionalProperties"], false);
        assert_eq!(schema["required"][0], "id");
        assert_eq!(schema["properties"]["id"]["type"], "string");
    }
}
