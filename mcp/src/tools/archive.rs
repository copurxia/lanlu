use crate::client::LanluApiClient;
use crate::protocol::{boolean_prop, string_prop, Tool};
use crate::tools::{object_schema, optional_bool, require_str};
use crate::utils::url_encode;
use serde_json::Value;
use std::collections::HashMap;

pub fn tool() -> Tool {
    Tool {
        name: "lanlu_archive_show",
        description: "Show archive metadata and optionally its page list.",
        input_schema: object_schema(
            "Return metadata for a single archive.",
            &["id"],
            vec![
                ("id", string_prop("Archive ID.")),
                (
                    "include_pages",
                    boolean_prop("Also return the list of pages."),
                ),
            ],
        ),
    }
}

pub async fn run_show(client: &LanluApiClient, args: &Value) -> Result<String, String> {
    let id = require_str(args, "id")?;
    let mut params: HashMap<&str, String> = HashMap::new();
    if optional_bool(args, "include_pages") {
        params.insert("include_pages", "true".to_string());
    }
    client
        .get(
            &format!("/api/archives/{}/metadata", url_encode(&id)),
            params,
        )
        .await
}
