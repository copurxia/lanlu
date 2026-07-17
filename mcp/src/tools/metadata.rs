use crate::client::LanluApiClient;
use crate::protocol::{string_prop, Tool};
use crate::tools::{object_schema, optional_str, require_str};
use crate::utils::url_encode;
use serde_json::Value;

pub fn tool() -> Tool {
    Tool {
        name: "lanlu_update_metadata",
        description: "Update metadata (title, description, tags, release date, cover) for an archive or tankoubon.",
        input_schema: object_schema(
            "Update metadata for a target archive or tankoubon.",
            &["id"],
            vec![
                ("id", string_prop("Archive or tankoubon ID.")),
                ("target_type", string_prop("Target type: archive (default) or tankoubon.")),
                ("title", string_prop("New title.")),
                ("description", string_prop("New description.")),
                ("tags", string_prop("New tags as comma-separated string or JSON array.")),
                ("release_at", string_prop("Release date string.")),
                ("cover", string_prop("Cover asset ID.")),
                ("namespace", string_prop("Metadata namespace.")),
            ],
        ),
    }
}

pub async fn run(client: &LanluApiClient, args: &Value) -> Result<String, String> {
    let id = require_str(args, "id")?;
    let target_type = optional_str(args, "target_type").unwrap_or_else(|| "archive".to_string());

    let mut body = serde_json::Map::new();

    if let Some(v) = optional_str(args, "title") {
        body.insert("title".to_string(), Value::String(v));
    }
    if let Some(v) = optional_str(args, "description") {
        body.insert("description".to_string(), Value::String(v));
    }
    if let Some(v) = optional_str(args, "tags") {
        let tag_val = match serde_json::from_str::<Value>(&v) {
            Ok(Value::Array(_)) => serde_json::from_str(&v).unwrap(),
            _ => Value::String(v),
        };
        body.insert("tags".to_string(), tag_val);
    }
    if let Some(v) = optional_str(args, "release_at") {
        body.insert("release_at".to_string(), Value::String(v));
    }
    if let Some(v) = optional_str(args, "cover") {
        body.insert("assets".to_string(), serde_json::json!({ "cover": v }));
    }
    if let Some(v) = optional_str(args, "namespace") {
        body.insert("metadata_namespace".to_string(), Value::String(v));
    }

    if body.is_empty() {
        return Err("at least one field to update is required".to_string());
    }

    let api_path = if target_type == "tankoubon" {
        format!("/api/tankoubons/{}/metadata", url_encode(&id))
    } else {
        format!("/api/archives/{}/metadata", url_encode(&id))
    };

    let payload = serde_json::to_string(&body).unwrap();
    client.put(&api_path, &payload).await
}
