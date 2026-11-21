use crate::client::LanluApiClient;
use crate::protocol::{string_prop, Tool};
use crate::tools::{object_schema, require_str};
use crate::utils::url_encode;
use serde_json::Value;

pub fn list_tool() -> Tool {
    Tool {
        name: "lanlu_tankoubon_list",
        description: "List all tankoubon collections.",
        input_schema: object_schema("No arguments.", &[], vec![]),
    }
}

pub fn show_tool() -> Tool {
    Tool {
        name: "lanlu_tankoubon_show",
        description: "Show metadata and contained archives for a tankoubon collection.",
        input_schema: object_schema(
            "Return details of a tankoubon.",
            &["id"],
            vec![("id", string_prop("Tankoubon ID."))],
        ),
    }
}

pub async fn run_list(client: &LanluApiClient, _args: &Value) -> Result<String, String> {
    client.get("/api/tankoubons", Default::default()).await
}

pub async fn run_show(client: &LanluApiClient, args: &Value) -> Result<String, String> {
    let id = require_str(args, "id")?;
    client
        .get(
            &format!("/api/tankoubons/{}/metadata", url_encode(&id)),
            Default::default(),
        )
        .await
}
