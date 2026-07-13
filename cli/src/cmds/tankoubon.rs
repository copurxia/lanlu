use crate::client::LanluApiClient;
use crate::output::{print_json_or_text, OutputMode};
use serde_json::Value;

pub async fn handle_tankoubon_list(
    client: &LanluApiClient,
    mode: OutputMode,
) -> Result<(), String> {
    let body = client.get("/api/tankoubons", Default::default()).await?;
    print_json_or_text(&body, mode, print_tankoubon_list);
    Ok(())
}

fn print_tankoubon_list(body: &str) {
    let root: Value =
        serde_json::from_str(body).expect("failed to parse tankoubon list");
    let items = root.get("result").and_then(|x| x.as_array());
    match items {
        Some(arr) if !arr.is_empty() => {
            println!("id\ttitle\tarchives\tpages\tcover_asset_id");
            for o in arr {
                let tid = get_str(o, "tankoubon_id");
                let title = get_str(o, "title");
                let count = o.get("archive_count").and_then(|x| x.as_i64()).unwrap_or(0);
                let pages = o.get("pagecount").and_then(|x| x.as_i64()).unwrap_or(0);
                let cover_id = o
                    .get("assets")
                    .and_then(|a| a.get("cover"))
                    .and_then(|c| c.as_i64())
                    .map(|c| c.to_string())
                    .unwrap_or_default();
                println!("{}\t{}\t{}\t{}\t{}", tid, title, count, pages, cover_id);
            }
        }
        _ => {
            println!("no tankoubon collections found");
        }
    }
}

pub async fn handle_tankoubon_show(
    client: &LanluApiClient,
    id: &str,
    mode: OutputMode,
) -> Result<(), String> {
    let body = client
        .get(
            &format!("/api/tankoubons/{}/metadata", url_encode(id)),
            Default::default(),
        )
        .await?;

    let printer = |b: &str| print_tankoubon_detail(b, client);
    if mode == OutputMode::Text {
        printer(&body);
    } else if mode == OutputMode::PrettyJson {
        match serde_json::from_str::<Value>(&body) {
            Ok(v) => println!("{}", serde_json::to_string_pretty(&v).unwrap()),
            Err(_) => println!("{}", body),
        }
    } else {
        println!("{}", body);
    }

    Ok(())
}

fn print_tankoubon_detail(body: &str, client: &LanluApiClient) {
    let root: Value =
        serde_json::from_str(body).expect("failed to parse tankoubon detail");

    let tid = get_str(&root, "tankoubon_id");
    let title = get_str(&root, "title");
    let desc = get_str(&root, "description");
    let tags = get_str(&root, "tags");
    let pagecount = root.get("pagecount").and_then(|x| x.as_i64()).unwrap_or(0);
    let archive_count = root
        .get("archive_count")
        .and_then(|x| x.as_i64())
        .unwrap_or(0);
    let progress = root.get("progress").and_then(|x| x.as_i64()).unwrap_or(0);
    let is_new = root.get("isnew").and_then(|x| x.as_bool()).unwrap_or(false);
    let is_fav = root
        .get("isfavorite")
        .and_then(|x| x.as_bool())
        .unwrap_or(false);

    println!("tankoubon_id:  {}", tid);
    println!("title:         {}", title);
    println!("description:   {}", desc);
    println!("tags:          {}", tags);
    println!("archive_count: {}", archive_count);
    println!("pagecount:     {}", pagecount);
    println!("progress:      {}%", progress);
    println!("isnew:         {}", is_new);
    println!("isfavorite:    {}", is_fav);

    if let Some(cover_id) = root
        .get("assets")
        .and_then(|a| a.get("cover"))
        .and_then(|c| c.as_i64())
    {
        if cover_id > 0 {
            let asset_url = format!("{}/api/assets/{}", client.get_host(), cover_id);
            println!("cover_asset_id: {}", cover_id);
            println!("cover_url:      {}", asset_url);
        }
    }

    if let Some(children) = root.get("children").and_then(|x| x.as_array()) {
        if !children.is_empty() {
            println!();
            println!("archives ({}):", children.len());
            for child in children {
                if let Some(s) = child.as_str() {
                    println!("  {}", s);
                } else if child.is_object() {
                    let eid = get_str(child, "entity_id");
                    let ct = get_str(child, "title");
                    println!("  {}  {}", eid, ct);
                }
            }
        }
    }
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
