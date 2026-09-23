use crate::client::LanluApiClient;
use crate::protocol::{boolean_prop, integer_prop, string_prop, Tool};
use crate::tools::{object_schema, optional_bool, optional_i64, optional_str};
use serde_json::Value;
use std::collections::HashMap;

/// Build the `/api/search` query map from tool arguments.
///
/// Extracted as a pure function so the parameter mapping is unit-testable
/// without an HTTP client.
pub fn build_search_params(args: &Value) -> HashMap<&'static str, String> {
    let mut params: HashMap<&'static str, String> = HashMap::new();

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

    params
}

pub fn tool() -> Tool {
    Tool {
        name: "lanlu_search",
        description: "Search the local archive library by keyword. Search keywords go in `filter`: free text, \"quoted phrases\", -exclusions, field:term (title:foo, tag:artist:bar).",
        input_schema: object_schema(
            "Search archives in the Lanlu library.",
            &[],
            vec![
                (
                    "filter",
                    string_prop(
                        "The search query. Free-text terms, \"exact phrases\", -excluded words, and field:term filters such as title:foo or tag:artist:bar.",
                    ),
                ),
                (
                    "category",
                    string_prop("Category ID to limit results to; list IDs via lanlu_category_list."),
                ),
                ("page", integer_prop("Page number, default 1.")),
                (
                    "page_size",
                    integer_prop("Items per page, default 20, max 200."),
                ),
                (
                    "sortby",
                    string_prop(
                        "Sort field: created_at, release_at, title or pagecount. Default title.",
                    ),
                ),
                ("order", string_prop("Sort direction: asc or desc. Default asc.")),
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
    let params = build_search_params(args);
    client.get("/api/search", params).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn maps_boolean_flags_as_true_strings() {
        let args = json!({
            "new_only": true,
            "untagged_only": true,
            "favorite_only": true,
            "group_by_tanks": true,
        });
        let p = build_search_params(&args);
        assert_eq!(p.get("newonly"), Some(&"true".to_string()));
        assert_eq!(p.get("untaggedonly"), Some(&"true".to_string()));
        assert_eq!(p.get("favoriteonly"), Some(&"true".to_string()));
        assert_eq!(p.get("groupby_tanks"), Some(&"true".to_string()));
    }

    #[test]
    fn omits_false_or_missing_flags() {
        let p = build_search_params(&json!({"new_only": false}));
        assert!(!p.contains_key("newonly"));
        assert!(!p.contains_key("untaggedonly"));
    }

    #[test]
    fn maps_pagination_sort_and_filters() {
        let args = json!({
            "page": 2,
            "page_size": 50,
            "sortby": "created_at",
            "order": "desc",
            "category": "c1",
            "filter": "title:foo",
        });
        let p = build_search_params(&args);
        assert_eq!(p.get("page"), Some(&"2".to_string()));
        assert_eq!(p.get("pageSize"), Some(&"50".to_string()));
        assert_eq!(p.get("sortby"), Some(&"created_at".to_string()));
        assert_eq!(p.get("order"), Some(&"desc".to_string()));
        assert_eq!(p.get("category"), Some(&"c1".to_string()));
        assert_eq!(p.get("filter"), Some(&"title:foo".to_string()));
    }

    #[test]
    fn skips_empty_filter_string() {
        let p = build_search_params(&json!({"filter": ""}));
        assert!(!p.contains_key("filter"));
    }

    #[test]
    fn empty_args_yield_empty_map() {
        let p = build_search_params(&json!({}));
        assert!(p.is_empty());
    }
}
