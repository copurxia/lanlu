use crate::client::LanluApiClient;
use crate::output::OutputMode;

pub async fn handle_update_metadata(
    client: &LanluApiClient,
    target_id: &str,
    target_type: &str,
    title: Option<&str>,
    description: Option<&str>,
    tags: Option<&str>,
    release_at: Option<&str>,
    cover: Option<&str>,
    namespace: Option<&str>,
    mode: OutputMode,
) -> Result<(), String> {
    let mut body = serde_json::Map::new();

    if let Some(v) = title {
        body.insert(
            "title".to_string(),
            serde_json::Value::String(v.to_string()),
        );
    }
    if let Some(v) = description {
        body.insert(
            "description".to_string(),
            serde_json::Value::String(v.to_string()),
        );
    }
    if let Some(v) = tags {
        // Try parsing as JSON array, otherwise use as string
        let tag_val = match serde_json::from_str::<serde_json::Value>(v) {
            Ok(serde_json::Value::Array(_)) => serde_json::from_str(v).unwrap(),
            _ => serde_json::Value::String(v.to_string()),
        };
        body.insert("tags".to_string(), tag_val);
    }
    if let Some(v) = release_at {
        body.insert(
            "release_at".to_string(),
            serde_json::Value::String(v.to_string()),
        );
    }
    if let Some(v) = cover {
        let assets = serde_json::json!({ "cover": v });
        body.insert("assets".to_string(), assets);
    }
    if let Some(v) = namespace {
        body.insert(
            "metadata_namespace".to_string(),
            serde_json::Value::String(v.to_string()),
        );
    }

    if body.is_empty() {
        return Err(
            "at least one field to update is required (--title, --description, --tags, --release-at, --cover)".to_string(),
        );
    }

    let api_path = if target_type == "tankoubon" {
        format!("/api/tankoubons/{}/metadata", url_encode(target_id))
    } else {
        format!("/api/archives/{}/metadata", url_encode(target_id))
    };

    let payload = serde_json::to_string(&body).unwrap();
    let resp_body = client.put(&api_path, &payload).await?;

    match mode {
        OutputMode::Text => {
            match serde_json::from_str::<serde_json::Value>(&resp_body) {
                Ok(root) => {
                    let success = root
                        .get("success")
                        .and_then(|x| x.as_i64())
                        .unwrap_or(0);
                    if success == 1 {
                        println!("metadata updated for {} {}", target_type, target_id);
                        if let Some(patched) = root.get("archives_patched") {
                            let skipped = root
                                .get("archives_skipped")
                                .and_then(|x| x.as_i64())
                                .unwrap_or(0);
                            println!(
                                "archives patched: {}, skipped: {}",
                                patched, skipped
                            );
                        }
                    } else {
                        println!("{}", resp_body);
                    }
                }
                Err(_) => println!("{}", resp_body),
            }
        }
        OutputMode::PrettyJson => {
            match serde_json::from_str::<serde_json::Value>(&resp_body) {
                Ok(v) => println!("{}", serde_json::to_string_pretty(&v).unwrap()),
                Err(_) => println!("{}", resp_body),
            }
        }
        OutputMode::Json => {
            println!("{}", resp_body);
        }
    }

    Ok(())
}

fn url_encode(s: &str) -> String {
    let mut result = String::new();
    for byte in s.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                result.push(byte as char);
            }
            b' ' => result.push_str("%20"),
            _ => {
                result.push_str(&format!("%{:02X}", byte));
            }
        }
    }
    result
}
