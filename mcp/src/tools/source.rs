use crate::client::LanluApiClient;
use crate::protocol::{boolean_prop, integer_prop, string_prop, Tool};
use crate::tools::{object_schema, optional_bool, optional_i64, optional_str, require_str};
use crate::utils::url_encode;
use serde_json::Value;

pub fn list_tool() -> Tool {
    Tool {
        name: "lanlu_source_list",
        description: "List available source plugins.",
        input_schema: object_schema("No arguments.", &[], vec![]),
    }
}

pub fn home_tool() -> Tool {
    Tool {
        name: "lanlu_source_home",
        description: "Call a source plugin's home/source_home action.",
        input_schema: object_schema(
            "Return the source plugin home listing.",
            &["namespace"],
            vec![("namespace", string_prop("Source plugin namespace."))],
        ),
    }
}

pub fn search_tool() -> Tool {
    Tool {
        name: "lanlu_source_search",
        description: "Search a source plugin.",
        input_schema: object_schema(
            "Search a source plugin.",
            &["namespace"],
            vec![
                ("namespace", string_prop("Source plugin namespace.")),
                ("query", string_prop("Search query.")),
                ("page", integer_prop("Page number.")),
                ("filters", string_prop("Filter conditions as JSON string.")),
            ],
        ),
    }
}

pub fn filters_tool() -> Tool {
    Tool {
        name: "lanlu_source_filters",
        description: "Get available filters for a source plugin.",
        input_schema: object_schema(
            "Return the source plugin filters.",
            &["namespace"],
            vec![("namespace", string_prop("Source plugin namespace."))],
        ),
    }
}

pub fn download_tool() -> Tool {
    Tool {
        name: "lanlu_source_download",
        description: "Download an item from a source plugin.",
        input_schema: object_schema(
            "Submit a source-plugin download task.",
            &["namespace", "remote_id", "category_id"],
            vec![
                ("namespace", string_prop("Source plugin namespace.")),
                ("remote_id", string_prop("Remote item ID.")),
                ("category_id", string_prop("Target category ID.")),
                ("kind", string_prop("Item kind, default archive.")),
                ("wait", boolean_prop("Wait for task completion.")),
                (
                    "interval",
                    integer_prop("Poll interval in ms, default 1000."),
                ),
                ("timeout", integer_prop("Timeout in ms, default 300000.")),
            ],
        ),
    }
}

pub async fn run_list(client: &LanluApiClient, _args: &Value) -> Result<String, String> {
    client
        .get("/api/admin/source-plugins", Default::default())
        .await
}

pub async fn run_home(client: &LanluApiClient, args: &Value) -> Result<String, String> {
    let namespace = require_str(args, "namespace")?;
    source_action(client, &namespace, "source_home", None).await
}

pub async fn run_search(client: &LanluApiClient, args: &Value) -> Result<String, String> {
    let namespace = require_str(args, "namespace")?;
    let query = optional_str(args, "query").unwrap_or_default();

    let mut payload = serde_json::Map::new();
    payload.insert("query".to_string(), Value::String(query));

    let page = optional_i64(args, "page").unwrap_or(1);
    payload.insert("page".to_string(), Value::Number(page.into()));

    if let Some(f) = optional_str(args, "filters") {
        match serde_json::from_str::<Value>(&f) {
            Ok(v) => {
                payload.insert("filters".to_string(), v);
            }
            Err(e) => return Err(format!("invalid filters JSON: {}", e)),
        }
    }

    let body = serde_json::to_string(&payload).unwrap();
    source_action(client, &namespace, "source_search", Some(&body)).await
}

pub async fn run_filters(client: &LanluApiClient, args: &Value) -> Result<String, String> {
    let namespace = require_str(args, "namespace")?;
    source_action(client, &namespace, "source_filters", None).await
}

pub async fn run_download(client: &LanluApiClient, args: &Value) -> Result<String, String> {
    let namespace = require_str(args, "namespace")?;
    let remote_id = require_str(args, "remote_id")?;
    let category_id = require_str(args, "category_id")?;
    let kind = optional_str(args, "kind").unwrap_or_else(|| "archive".to_string());
    let wait = optional_bool(args, "wait");
    let interval = optional_i64(args, "interval").unwrap_or(1000) as u64;
    let timeout = optional_i64(args, "timeout").unwrap_or(300000) as u64;

    let payload = serde_json::json!({
        "remote_id": remote_id,
        "category_id": category_id,
        "kind": kind,
    });

    let resp = client
        .post(
            &format!(
                "/api/admin/source-plugins/{}/download",
                url_encode(&namespace)
            ),
            &payload.to_string(),
        )
        .await?;

    handle_task_response(client, &resp, wait, interval, timeout).await
}

async fn source_action(
    client: &LanluApiClient,
    namespace: &str,
    action: &str,
    payload_str: Option<&str>,
) -> Result<String, String> {
    let payload = payload_str.unwrap_or("{}");
    client
        .post(
            &format!(
                "/api/admin/source-plugins/{}/action/{}",
                url_encode(namespace),
                action
            ),
            payload,
        )
        .await
}

pub(crate) async fn handle_task_response(
    client: &LanluApiClient,
    resp: &str,
    wait: bool,
    interval: u64,
    timeout: u64,
) -> Result<String, String> {
    let root: Value = serde_json::from_str(resp).map_err(|e| format!("JSON parse error: {}", e))?;

    if wait {
        let task_id = root
            .get("task_id")
            .and_then(|x| x.as_i64())
            .or_else(|| root.get("job").and_then(|x| x.as_i64()))
            .unwrap_or(0);
        if task_id > 0 {
            let result = super::task::wait_for_task(client, task_id, interval, timeout).await?;
            return Ok(serde_json::to_string(&result).unwrap());
        }
    }

    Ok(resp.to_string())
}
