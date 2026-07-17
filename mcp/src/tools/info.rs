use crate::client::LanluApiClient;
use crate::protocol::Tool;
use crate::tools::object_schema;
use serde_json::Value;

pub fn tool() -> Tool {
    Tool {
        name: "lanlu_info",
        description: "Get Lanlu server information and statistics.",
        input_schema: object_schema("No arguments.", &[], vec![]),
    }
}

pub async fn run(client: &LanluApiClient, _args: &Value) -> Result<String, String> {
    client.get("/api/info", Default::default()).await
}
