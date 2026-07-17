use crate::client::LanluApiClient;
use crate::protocol::{boolean_prop, integer_prop, string_prop, Tool};
use crate::tools::{object_schema, optional_bool, optional_i64, require_str};
use serde_json::Value;
use std::collections::HashMap;
use tokio::time::{sleep, Duration};

pub fn tool() -> Tool {
    Tool {
        name: "lanlu_task",
        description: "Get the status of a background task.",
        input_schema: object_schema(
            "Return task status and progress.",
            &["id"],
            vec![
                ("id", string_prop("Task ID.")),
                (
                    "interval",
                    integer_prop("Poll interval in ms if waiting, default 1000."),
                ),
                (
                    "timeout",
                    integer_prop("Timeout in ms if waiting, default 300000."),
                ),
                ("wait", boolean_prop("Wait until the task completes.")),
            ],
        ),
    }
}

pub async fn run(client: &LanluApiClient, args: &Value) -> Result<String, String> {
    let id = require_str(args, "id")?;
    let wait = optional_bool(args, "wait");
    let interval = optional_i64(args, "interval").unwrap_or(1000) as u64;
    let timeout = optional_i64(args, "timeout").unwrap_or(300000) as u64;

    let task_id: i64 = id.parse().map_err(|_| format!("invalid task id: {}", id))?;

    if wait {
        let result = wait_for_task(client, task_id, interval, timeout).await?;
        return Ok(serde_json::to_string(&result).unwrap());
    }

    client
        .get(&format!("/api/admin/taskpool/{}", task_id), HashMap::new())
        .await
}

/// Poll a task until it reaches a terminal state or times out.
pub async fn wait_for_task(
    client: &LanluApiClient,
    task_id: i64,
    interval_ms: u64,
    timeout_ms: u64,
) -> Result<Value, String> {
    let max_iter = if timeout_ms == 0 || interval_ms == 0 {
        1
    } else {
        std::cmp::max(timeout_ms / interval_ms, 1)
    };

    for _ in 0..max_iter {
        let body = client
            .get(&format!("/api/admin/taskpool/{}", task_id), HashMap::new())
            .await?;

        let root: Value =
            serde_json::from_str(&body).map_err(|e| format!("JSON parse error: {}", e))?;

        let status = root.get("status").and_then(|x| x.as_str()).unwrap_or("");
        if status == "completed" || status == "failed" || status == "stopped" {
            return Ok(root);
        }

        sleep(Duration::from_millis(interval_ms)).await;
    }

    Err(format!(
        "task {} did not finish within {}ms",
        task_id, timeout_ms
    ))
}
