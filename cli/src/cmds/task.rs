use crate::client::LanluApiClient;
use crate::output::{print_raw, OutputMode};
use serde_json::Value;
use std::collections::HashMap;
use tokio::time::{sleep, Duration};

pub async fn handle_task(
    client: &LanluApiClient,
    task_id_str: &str,
    mode: OutputMode,
) -> Result<(), String> {
    let task_id: i64 = task_id_str
        .parse()
        .map_err(|_| format!("invalid task id: {}", task_id_str))?;

    let body = client
        .get(
            &format!("/api/admin/taskpool/{}", task_id),
            HashMap::new(),
        )
        .await?;

    print_raw(&body, mode);
    Ok(())
}

pub async fn wait_for_task(
    client: &LanluApiClient,
    task_id: i64,
    interval_ms: u64,
    timeout_ms: u64,
    mode: OutputMode,
) -> Result<Value, String> {
    let max_iter = if timeout_ms == 0 || interval_ms == 0 {
        1
    } else {
        std::cmp::max(timeout_ms / interval_ms, 1)
    };

    for _i in 0..max_iter {
        let body = client
            .get(
                &format!("/api/admin/taskpool/{}", task_id),
                HashMap::new(),
            )
            .await?;

        let root: Value =
            serde_json::from_str(&body).map_err(|e| format!("JSON parse error: {}", e))?;

        let status = root
            .get("status")
            .and_then(|x| x.as_str())
            .unwrap_or("");
        let progress = root
            .get("progress")
            .and_then(|x| x.as_i64())
            .unwrap_or(0);
        let message = root
            .get("message")
            .and_then(|x| x.as_str())
            .unwrap_or("");

        if mode == OutputMode::Text {
            println!(
                "[task {}] status={} progress={}% {}",
                task_id, status, progress, message
            );
        }

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
