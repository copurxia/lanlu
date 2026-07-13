use crate::client::LanluApiClient;
use crate::output::{print_raw, OutputMode};
use crate::cmds::task::wait_for_task;
use serde_json::Value;
use std::collections::HashMap;
use std::fs;
use std::path::Path;

pub async fn handle_download_url(
    client: &LanluApiClient,
    url: &str,
    category_id: &str,
    wait: bool,
    interval: u64,
    timeout: u64,
    mode: OutputMode,
) -> Result<(), String> {
    let payload = serde_json::json!({
        "url": url,
        "category_id": category_id,
    });

    let resp_body = client
        .post("/api/download_url", &payload.to_string())
        .await?;

    if mode != OutputMode::Text {
        print_raw(&resp_body, mode);
        return Ok(());
    }

    let root: Value =
        serde_json::from_str(&resp_body).map_err(|e| format!("JSON parse error: {}", e))?;
    let job = root.get("job").and_then(|x| x.as_i64()).unwrap_or(0);
    if job <= 0 {
        println!("{}", resp_body);
        return Ok(());
    }

    println!("created download task: {}", job);

    if wait {
        let result = wait_for_task(client, job, interval, timeout, mode).await?;
        println!("{}", serde_json::to_string(&result).unwrap());
    }

    Ok(())
}

pub async fn handle_upload(
    client: &LanluApiClient,
    file_path: &str,
    category_id: &str,
    chunk_size: usize,
    target_type: &str,
    overwrite: bool,
    wait: bool,
    interval: u64,
    timeout: u64,
    mode: OutputMode,
) -> Result<(), String> {
    let all_bytes = fs::read(file_path).map_err(|e| format!("read file failed: {}", e))?;
    let file_size = all_bytes.len();
    let filename = Path::new(file_path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown");

    let total_chunks = (file_size + chunk_size - 1) / chunk_size;

    let init_payload = serde_json::json!({
        "filename": filename,
        "filesize": file_size,
        "chunk_size": chunk_size,
        "total_chunks": total_chunks,
        "category_id": category_id,
        "target_type": target_type,
        "overwrite": overwrite,
    });

    let init_resp = client
        .post("/api/assets/upload/init", &init_payload.to_string())
        .await?;

    let init_root: Value = serde_json::from_str(&init_resp)
        .map_err(|e| format!("failed to parse upload init: {}", e))?;
    let task_id_str = init_root
        .get("taskId")
        .and_then(|x| x.as_str())
        .ok_or_else(|| "missing taskId in upload init response".to_string())?;
    let task_id: i64 = task_id_str
        .parse()
        .map_err(|_| "invalid taskId".to_string())?;

    if mode == OutputMode::Text {
        println!("upload session: {}, total chunks: {}", task_id, total_chunks);
    }

    let mut offset = 0;
    for i in 0..total_chunks {
        let end = std::cmp::min(offset + chunk_size, file_size);
        let chunk = all_bytes[offset..end].to_vec();

        let mut query = HashMap::new();
        query.insert("taskId", task_id_str.to_string());
        query.insert("chunkIndex", i.to_string());
        query.insert("totalChunks", total_chunks.to_string());

        let chunk_body = client
            .put_bytes("/api/assets/upload/chunk", query, chunk)
            .await?;

        if mode == OutputMode::Text {
            println!("chunk {}/{} uploaded", i + 1, total_chunks);
        }
        if mode == OutputMode::Json || mode == OutputMode::PrettyJson {
            println!("{}", chunk_body);
        }

        offset = end;
    }

    if wait {
        let result = wait_for_task(client, task_id, interval, timeout, mode).await?;
        println!("{}", serde_json::to_string(&result).unwrap());
    }

    Ok(())
}

pub async fn handle_metadata_run(
    client: &LanluApiClient,
    namespace: &str,
    target_id: &str,
    target_type: &str,
    param: &str,
    write_back: bool,
    wait: bool,
    interval: u64,
    timeout: u64,
    mode: OutputMode,
) -> Result<(), String> {
    let mut payload = serde_json::json!({
        "target_type": target_type,
        "target_id": target_id,
        "namespace": namespace,
        "write_back": if write_back { "1" } else { "0" },
    });

    if !param.is_empty() {
        payload
            .as_object_mut()
            .unwrap()
            .insert("param".to_string(), Value::String(param.to_string()));
    }

    let resp_body = client
        .post("/api/metadata_plugin", &payload.to_string())
        .await?;

    if mode != OutputMode::Text {
        print_raw(&resp_body, mode);
        return Ok(());
    }

    let root: Value =
        serde_json::from_str(&resp_body).map_err(|e| format!("JSON parse error: {}", e))?;
    let job = root.get("job").and_then(|x| x.as_i64()).unwrap_or(0);
    if job <= 0 {
        println!("{}", resp_body);
        return Ok(());
    }

    println!("created metadata task: {}", job);

    if wait {
        let result = wait_for_task(client, job, interval, timeout, mode).await?;
        println!("{}", serde_json::to_string(&result).unwrap());
    }

    Ok(())
}
