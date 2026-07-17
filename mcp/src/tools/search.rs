use crate::client::LanluApiClient;
use crate::protocol::{boolean_prop, integer_prop, string_prop, Tool};
use crate::tools::{object_schema, optional_bool, optional_i64, optional_str};
use serde_json::Value;
use std::collections::HashMap;

pub fn tool() -> Tool {
    Tool {
        name: "lanlu_search",
        description: "Search archives with optional filters, pagination and sorting.",
        input_schema: object_schema(
            "Search archives in the Lanlu library.",
            &[],
            vec![
                (
                    "filter",
                    string_prop("Search filter, e.g. title:foo or tag:artist:bar."),
                ),
                ("category", string_prop("Category ID to filter by.")),
                ("page", integer_prop("Page number.")),
                ("page_size", integer_prop("Number of items per page.")),
                (
                    "sortby",
                    string_prop("Sort field such as created_at, release_at, title, pagecount."),
                ),
                ("order", string_prop("Sort order: asc or desc.")),
                ("new_only", boolean_prop("Only show new archives.")),
                (
                    "untagged_only",
                    boolean_prop("Only show archives without tags."),
                ),
                (
                    "favorite_only",
                    boolean_prop("Only show favorite archives."),
                ),
                (
                    "group_by_tanks",
                    boolean_prop("Group results by tankoubon collections."),
                ),
            ],
        ),
    }
}

pub async fn run(client: &LanluApiClient, args: &Value) -> Result<String, String> {
    let mut params: HashMap<&str, String> = HashMap::new();

    if let Some(v) = optional_str(args, "filter") {
        if !v.is_empty() {
            params.insert("filter", v);
        }
    }
    if let Some(v) = optional_str(args, "category") {
        params.insert("category", v);
    }
    if let Some(v) = optional_i64(args, "page") {
        params.insert("page", v.to_string());
    }
    if let Some(v) = optional_i64(args, "page_size") {
        params.insert("pageSize", v.to_string());
    }
    if let Some(v) = optional_str(args, "sortby") {
        params.insert("sortby", v);
    }
    if let Some(v) = optional_str(args, "order") {
        params.insert("order", v);
    }
    if optional_bool(args, "new_only") {
        params.insert("newonly", "true".to_string());
    }
    if optional_bool(args, "untagged_only") {
        params.insert("untaggedonly", "true".to_string());
    }
    if optional_bool(args, "favorite_only") {
        params.insert("favoriteonly", "true".to_string());
    }
    if optional_bool(args, "group_by_tanks") {
        params.insert("groupby_tanks", "true".to_string());
    }

    client.get("/api/search", params).await
}
