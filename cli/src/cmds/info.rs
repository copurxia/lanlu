use crate::client::LanluApiClient;
use crate::output::{print_raw, OutputMode};
use serde_json::Value;

pub async fn handle_info(client: &LanluApiClient, mode: OutputMode) -> Result<(), String> {
    let body = client.get("/api/info", Default::default()).await?;

    if mode != OutputMode::Text {
        print_raw(&body, mode);
        return Ok(());
    }

    let v: Value = serde_json::from_str(&body).map_err(|e| format!("JSON parse error: {}", e))?;

    println!(
        "Server:       {}",
        v.get("name").and_then(|x| x.as_str()).unwrap_or("(unknown)")
    );
    println!(
        "MOTD:         {}",
        v.get("motd").and_then(|x| x.as_str()).unwrap_or("")
    );
    println!(
        "Version:      {}",
        v.get("version_desc").and_then(|x| x.as_str()).unwrap_or("")
    );
    println!(
        "Runtime:      {}",
        v.get("version_name").and_then(|x| x.as_str()).unwrap_or("")
    );
    println!(
        "Archives:     {}",
        v.get("total_archives").and_then(|x| x.as_i64()).unwrap_or(0)
    );
    println!(
        "Pages read:   {}",
        v.get("total_pages_read").and_then(|x| x.as_i64()).unwrap_or(0)
    );

    if let Some(exts) = v.get("db_extensions").and_then(|x| x.as_array()) {
        if !exts.is_empty() {
            println!("DB Extensions:");
            for ext in exts {
                let name = ext.get("name").and_then(|x| x.as_str()).unwrap_or("");
                let enabled = if ext.get("enabled").and_then(|x| x.as_bool()).unwrap_or(false) {
                    "enabled"
                } else {
                    "disabled"
                };
                let ver = ext.get("version").and_then(|x| x.as_str()).unwrap_or("");
                println!("  {}: {} ({})", name, enabled, ver);
            }
        }
    }

    Ok(())
}
