use crate::client::LanluApiClient;
use crate::output::{print_json_or_text, print_raw, OutputMode};
use serde_json::Value;
use std::collections::HashMap;

pub async fn handle_search(
    client: &LanluApiClient,
    filter: &str,
    category: Option<&str>,
    page: Option<&str>,
    page_size: Option<&str>,
    sortby: Option<&str>,
    order: Option<&str>,
    new_only: bool,
    untagged_only: bool,
    favorite_only: bool,
    group_by_tanks: bool,
    mode: OutputMode,
) -> Result<(), String> {
    let mut params: HashMap<&str, String> = HashMap::new();
    if !filter.is_empty() {
        params.insert("filter", filter.to_string());
    }
    if let Some(v) = category {
        params.insert("category", v.to_string());
    }
    if let Some(v) = page {
        params.insert("page", v.to_string());
    }
    if let Some(v) = page_size {
        params.insert("pageSize", v.to_string());
    }
    if let Some(v) = sortby {
        params.insert("sortby", v.to_string());
    }
    if let Some(v) = order {
        params.insert("order", v.to_string());
    }
    if new_only {
        params.insert("newonly", "true".to_string());
    }
    if untagged_only {
        params.insert("untaggedonly", "true".to_string());
    }
    if favorite_only {
        params.insert("favoriteonly", "true".to_string());
    }
    if group_by_tanks {
        params.insert("groupby_tanks", "true".to_string());
    }

    let body = client.get("/api/search", params).await?;

    if mode != OutputMode::Text {
        print_raw(&body, mode);
        return Ok(());
    }

    let root: Value =
        serde_json::from_str(&body).map_err(|e| format!("failed to parse search result: {}", e))?;

    if let Some(data) = root.get("data").and_then(|x| x.as_array()) {
        print_search_items(data);
    }

    if let Some(groups) = root.get("groups").and_then(|x| x.as_array()) {
        for g in groups {
            println!();
            let cid = get_str(g, "category_id");
            println!("group category_id={}", cid);
            if let Some(items) = g.get("data").and_then(|x| x.as_array()) {
                print_search_items(items);
            }
        }
    }

    let total = root
        .get("recordsTotal")
        .and_then(|x| x.as_i64())
        .unwrap_or(0);
    println!("total: {}", total);

    Ok(())
}

fn print_search_items(data: &[Value]) {
    for o in data {
        let item_type = get_str(o, "type");
        if item_type == "tankoubon" {
            let tid = get_str(o, "tankoubon_id");
            let title = get_str(o, "title");
            let count = o.get("archive_count").and_then(|x| x.as_i64()).unwrap_or(0);
            let children = o.get("children").and_then(|x| x.as_array());
            let child_info = match children {
                Some(c) if !c.is_empty() => format!(", {} children", c.len()),
                _ => String::new(),
            };
            let cover_id = o
                .get("assets")
                .and_then(|a| a.get("cover"))
                .and_then(|c| c.as_i64())
                .map(|c| format!(", cover={}", c))
                .unwrap_or_default();
            println!(
                "[tank] {} {} ({} archives{}){}",
                tid, title, count, child_info, cover_id
            );
        } else {
            let arcid = get_str(o, "arcid");
            let title = get_str(o, "title");
            let pagecount = o.get("pagecount").and_then(|x| x.as_i64()).unwrap_or(0);
            let tags = get_str(o, "tags");
            let cover_info = o
                .get("assets")
                .and_then(|a| a.get("cover"))
                .and_then(|c| c.as_i64())
                .map(|c| format!(" cover={}", c))
                .unwrap_or_default();
            println!("{} | {} | {}p | {}{}", arcid, title, pagecount, tags, cover_info);
        }
    }
}

pub async fn handle_archive_show(
    client: &LanluApiClient,
    arcid: &str,
    include_pages: bool,
    mode: OutputMode,
) -> Result<(), String> {
    let mut params: HashMap<&str, String> = HashMap::new();
    if include_pages {
        params.insert("include_pages", "true".to_string());
    }
    let body = client
        .get(&format!("/api/archives/{}/metadata", url_encode(arcid)), params)
        .await?;

    print_json_or_text(&body, mode, print_archive_detail);

    Ok(())
}

fn print_archive_detail(body: &str) {
    let root: Value =
        serde_json::from_str(body).expect("failed to parse archive detail");
    println!("arcid: {}", get_str(&root, "arcid"));
    println!("title: {}", get_str(&root, "title"));
    println!("filename: {}", get_str(&root, "filename"));
    println!(
        "pagecount: {}",
        root.get("pagecount").and_then(|x| x.as_i64()).unwrap_or(0)
    );
    println!(
        "archivetype: {}",
        get_str(&root, "archivetype")
    );
    println!("tags: {}", get_str(&root, "tags"));
    println!("description: {}", get_str(&root, "description"));

    let cover_id = root
        .get("cover_asset_id")
        .and_then(|x| x.as_i64())
        .unwrap_or(0);
    if cover_id > 0 {
        println!("cover_asset_id: {}", cover_id);
    }

    if let Some(pages) = root.get("pages").and_then(|x| x.as_array()) {
        println!("pages: {}", pages.len());
    }
}

pub async fn handle_category_list(
    client: &LanluApiClient,
    mode: OutputMode,
) -> Result<(), String> {
    let body = client.get("/api/categories", Default::default()).await?;

    if mode != OutputMode::Text {
        print_raw(&body, mode);
        return Ok(());
    }

    let root: Value =
        serde_json::from_str(&body).map_err(|e| format!("failed to parse categories: {}", e))?;

    let arr = root.get("data").and_then(|x| x.as_array());
    match arr {
        Some(items) => {
            println!("id\tname\tcount");
            for o in items {
                let id = o.get("id").and_then(|x| x.as_str()).unwrap_or("");
                let name = get_str(o, "name");
                let count = o
                    .get("archive_count")
                    .and_then(|x| x.as_i64())
                    .unwrap_or(0);
                println!("{}\t{}\t{}", id, name, count);
            }
        }
        None => {
            println!("{}", body);
        }
    }

    Ok(())
}

fn get_str(v: &Value, key: &str) -> String {
    v.get(key)
        .and_then(|x| x.as_str())
        .unwrap_or("")
        .to_string()
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
