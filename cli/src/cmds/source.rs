use crate::client::LanluApiClient;
use crate::output::{print_json_or_text, print_raw, OutputMode};
use crate::cmds::task::wait_for_task;
use serde_json::Value;

pub async fn handle_source_list(
    client: &LanluApiClient,
    mode: OutputMode,
) -> Result<(), String> {
    let body = client.get("/api/admin/source-plugins", Default::default()).await?;
    print_json_or_text(&body, mode, print_source_list);
    Ok(())
}

fn print_source_list(body: &str) {
    let arr: Vec<Value> =
        serde_json::from_str(body).unwrap_or_default();
    println!("namespace\tname\tenabled");
    for o in &arr {
        let ns = get_str(o, "namespace");
        let name = get_str(o, "name");
        let enabled = o.get("enabled").and_then(|x| x.as_bool()).unwrap_or(false);
        println!("{}\t{}\t{}", ns, name, enabled);
    }
}

pub async fn handle_source_home(
    client: &LanluApiClient,
    namespace: &str,
    mode: OutputMode,
) -> Result<(), String> {
    handle_source_action(client, namespace, "source_home", None, mode).await
}

pub async fn handle_source_search(
    client: &LanluApiClient,
    namespace: &str,
    query: &str,
    page: Option<&str>,
    filters: Option<&str>,
    mode: OutputMode,
) -> Result<(), String> {
    let mut payload = serde_json::Map::new();
    payload.insert("query".to_string(), Value::String(query.to_string()));

    let page_num: i64 = page
        .and_then(|p| p.parse().ok())
        .unwrap_or(1);
    payload.insert("page".to_string(), Value::Number(page_num.into()));

    if let Some(f) = filters {
        match serde_json::from_str::<Value>(f) {
            Ok(v) => {
                payload.insert("filters".to_string(), v);
            }
            Err(e) => return Err(format!("invalid --filters JSON: {}", e)),
        }
    }

    let body_str = serde_json::to_string(&payload).unwrap();
    handle_source_action(client, namespace, "source_search", Some(&body_str), mode).await
}

pub async fn handle_source_filters(
    client: &LanluApiClient,
    namespace: &str,
    mode: OutputMode,
) -> Result<(), String> {
    handle_source_action(client, namespace, "source_filters", None, mode).await
}

async fn handle_source_action(
    client: &LanluApiClient,
    namespace: &str,
    action: &str,
    payload_str: Option<&str>,
    mode: OutputMode,
) -> Result<(), String> {
    let payload = payload_str.unwrap_or("{}");
    let body = client
        .post(
            &format!("/api/admin/source-plugins/{}/action/{}", url_encode(namespace), action),
            payload,
        )
        .await?;
    print_json_or_text(&body, mode, print_source_items);
    Ok(())
}

fn print_source_items(body: &str) {
    let root: Value =
        serde_json::from_str(body).expect("failed to parse source action result");
    let data = match root.get("data") {
        Some(d) if d.is_object() => d.as_object().unwrap(),
        _ => {
            println!("{}", body);
            return;
        }
    };
    let items = match data.get("items").and_then(|x| x.as_array()) {
        Some(v) => v,
        _ => {
            println!("{}", body);
            return;
        }
    };
    for o in items {
        let title = get_str(o, "title");
        let remote_id = get_str(o, "remote_id");
        let kind = get_str(o, "kind");
        let kind = if kind.is_empty() { "archive" } else { &kind };
        println!("[{}] {} {}", kind, remote_id, title);
    }
}

pub async fn handle_source_download(
    client: &LanluApiClient,
    namespace: &str,
    remote_id: &str,
    category_id: &str,
    kind: &str,
    wait: bool,
    interval: u64,
    timeout: u64,
    mode: OutputMode,
) -> Result<(), String> {
    let payload = serde_json::json!({
        "remote_id": remote_id,
        "category_id": category_id,
        "kind": kind,
    });

    let resp_body = client
        .post(
            &format!("/api/admin/source-plugins/{}/download", url_encode(namespace)),
            &payload.to_string(),
        )
        .await?;

    if mode != OutputMode::Text {
        print_raw(&resp_body, mode);
        return Ok(());
    }

    let root: Value =
        serde_json::from_str(&resp_body).map_err(|e| format!("JSON parse error: {}", e))?;
    let task_id = root.get("task_id").and_then(|x| x.as_i64()).unwrap_or(0);
    if task_id <= 0 {
        println!("{}", resp_body);
        return Ok(());
    }

    println!("created source download task: {}", task_id);

    if wait {
        let result = wait_for_task(client, task_id, interval, timeout, mode).await?;
        println!("{}", serde_json::to_string(&result).unwrap());
    }

    Ok(())
}

fn get_str<'a>(v: &'a Value, key: &str) -> &'a str {
    v.get(key).and_then(|x| x.as_str()).unwrap_or("")
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
