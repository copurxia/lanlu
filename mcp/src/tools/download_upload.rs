use crate::client::LanluApiClient;
use crate::protocol::{boolean_prop, integer_prop, string_prop, Tool};
use crate::tools::{object_schema, optional_bool, optional_i64, optional_str, require_str};
use serde_json::Value;
use std::collections::HashMap;
use std::path::Path;
use tokio::io::AsyncReadExt;

/// Number of chunks of `chunk_size` needed to cover `file_size` bytes.
///
/// Uses ceiling division so a partial final chunk still counts.
pub fn total_chunks(file_size: usize, chunk_size: usize) -> usize {
    file_size.div_ceil(chunk_size)
}

pub fn download_url_tool() -> Tool {
    Tool {
        name: "lanlu_download_url",
        description: "Submit a URL to the server for server-side download and ingestion.",
        input_schema: object_schema(
            "Submit a URL download task.",
            &["url", "category_id"],
            vec![
                ("url", string_prop("URL to download.")),
                ("category_id", string_prop("Target category ID.")),
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

pub fn upload_tool() -> Tool {
    Tool {
        name: "lanlu_upload",
        description: "Upload a local file to Lanlu in chunks.",
        input_schema: object_schema(
            "Upload a local file.",
            &["file", "category_id"],
            vec![
                ("file", string_prop("Local file path to upload.")),
                ("category_id", string_prop("Target category ID.")),
                (
                    "chunk_size",
                    integer_prop("Chunk size in bytes, default 8388608 (8MB)."),
                ),
                ("target_type", string_prop("Target type, default archive.")),
                ("overwrite", boolean_prop("Overwrite if exists.")),
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

pub fn metadata_run_tool() -> Tool {
    Tool {
        name: "lanlu_metadata_run",
        description: "Run a metadata plugin against an archive or tankoubon.",
        input_schema: object_schema(
            "Run a metadata plugin.",
            &["namespace", "target_id"],
            vec![
                ("namespace", string_prop("Metadata plugin namespace.")),
                ("target_id", string_prop("Target ID.")),
                ("target_type", string_prop("Target type, default archive.")),
                ("param", string_prop("Plugin parameter.")),
                (
                    "write_back",
                    boolean_prop("Write results back to metadata."),
                ),
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

pub async fn run_download_url(client: &LanluApiClient, args: &Value) -> Result<String, String> {
    let url = require_str(args, "url")?;
    let category_id = require_str(args, "category_id")?;
    let wait = optional_bool(args, "wait");
    let interval = optional_i64(args, "interval").unwrap_or(1000) as u64;
    let timeout = optional_i64(args, "timeout").unwrap_or(300000) as u64;

    let payload = serde_json::json!({
        "url": url,
        "category_id": category_id,
    });

    let resp = client
        .post("/api/download_url", &payload.to_string())
        .await?;
    super::source::handle_task_response(client, &resp, wait, interval, timeout).await
}

pub async fn run_upload(client: &LanluApiClient, args: &Value) -> Result<String, String> {
    let file_path = require_str(args, "file")?;
    let category_id = require_str(args, "category_id")?;
    let chunk_size = optional_i64(args, "chunk_size").unwrap_or(8388608) as usize;
    let target_type = optional_str(args, "target_type").unwrap_or_else(|| "archive".to_string());
    let overwrite = optional_bool(args, "overwrite");
    let wait = optional_bool(args, "wait");
    let interval = optional_i64(args, "interval").unwrap_or(1000) as u64;
    let timeout = optional_i64(args, "timeout").unwrap_or(300000) as u64;

    let metadata = tokio::fs::metadata(&file_path)
        .await
        .map_err(|e| format!("stat file failed: {}", e))?;
    let file_size = metadata.len() as usize;
    let filename = Path::new(&file_path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown");

    let total_chunks = total_chunks(file_size, chunk_size);

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

    // Stream the file off disk one chunk at a time rather than loading the
    // whole archive into memory, so large uploads stay within a bounded
    // resident footprint.
    let mut file = tokio::fs::File::open(&file_path)
        .await
        .map_err(|e| format!("open file failed: {}", e))?;

    for i in 0..total_chunks {
        let remaining = file_size - i * chunk_size;
        let mut chunk = vec![0u8; std::cmp::min(chunk_size, remaining)];
        file.read_exact(&mut chunk)
            .await
            .map_err(|e| format!("read chunk {} failed: {}", i, e))?;

        let mut query = HashMap::new();
        query.insert("taskId", task_id_str.to_string());
        query.insert("chunkIndex", i.to_string());
        query.insert("totalChunks", total_chunks.to_string());

        client
            .put_bytes("/api/assets/upload/chunk", query, chunk)
            .await?;
    }

    if wait {
        let result = super::task::wait_for_task(client, task_id, interval, timeout).await?;
        return Ok(serde_json::to_string(&result).unwrap());
    }

    Ok(serde_json::json!({ "task_id": task_id, "uploaded": true }).to_string())
}

pub async fn run_metadata_run(client: &LanluApiClient, args: &Value) -> Result<String, String> {
    let namespace = require_str(args, "namespace")?;
    let target_id = require_str(args, "target_id")?;
    let target_type = optional_str(args, "target_type").unwrap_or_else(|| "archive".to_string());
    let param = optional_str(args, "param").unwrap_or_default();
    let write_back = optional_bool(args, "write_back");
    let wait = optional_bool(args, "wait");
    let interval = optional_i64(args, "interval").unwrap_or(1000) as u64;
    let timeout = optional_i64(args, "timeout").unwrap_or(300000) as u64;

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
            .insert("param".to_string(), Value::String(param));
    }

    let resp = client
        .post("/api/metadata_plugin", &payload.to_string())
        .await?;
    super::source::handle_task_response(client, &resp, wait, interval, timeout).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn total_chunks_exact_multiple() {
        assert_eq!(total_chunks(16, 8), 2);
    }

    #[test]
    fn total_chunks_with_remainder() {
        assert_eq!(total_chunks(20, 8), 3);
    }

    #[test]
    fn total_chunks_single_partial_chunk() {
        assert_eq!(total_chunks(1, 8), 1);
    }

    #[test]
    fn total_chunks_zero_size_is_zero() {
        assert_eq!(total_chunks(0, 8), 0);
    }
}
