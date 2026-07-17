use crate::client::LanluApiClient;
use crate::protocol::{string_prop, Tool};
use crate::tools::{object_schema, optional_str};
use crate::utils::url_encode;
use serde_json::Value;

pub fn tool() -> Tool {
    Tool {
        name: "lanlu_cover",
        description: "Get cover asset information for an archive/tankoubon or a known asset ID.",
        input_schema: object_schema(
            "Return cover information.",
            &[],
            vec![
                ("id", string_prop("Archive or tankoubon ID.")),
                ("asset_id", string_prop("Known cover asset ID.")),
            ],
        ),
    }
}

pub async fn run(client: &LanluApiClient, args: &Value) -> Result<String, String> {
    if let Some(asset_id) = optional_str(args, "asset_id") {
        let url = format!("{}/api/assets/{}", client.get_host(), asset_id);
        return Ok(serde_json::json!({ "asset_id": asset_id, "asset_url": url }).to_string());
    }

    let id = optional_str(args, "id")
        .ok_or_else(|| "either 'id' or 'asset_id' is required".to_string())?;

    client
        .get(
            &format!("/api/archives/{}/cover", url_encode(&id)),
            Default::default(),
        )
        .await
}
