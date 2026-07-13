use crate::client::LanluApiClient;
use crate::output::{print_raw, OutputMode};
use serde_json::Value;

pub async fn handle_cover(
    client: &LanluApiClient,
    target_id: Option<&str>,
    asset_id: Option<&str>,
    mode: OutputMode,
) -> Result<(), String> {
    if let Some(aid) = asset_id {
        show_asset_url(client, aid, mode);
        return Ok(());
    }

    let target_id = match target_id {
        Some(id) => id,
        None => return Err("usage: cover <archive-id|tankoubon-id>  or  cover --asset-id <id>".to_string()),
    };

    let body = client
        .get(
            &format!("/api/archives/{}/cover", url_encode(target_id)),
            Default::default(),
        )
        .await?;

    let root: Value =
        serde_json::from_str(&body).map_err(|e| format!("failed to parse cover: {}", e))?;

    let cover_asset_id = root
        .get("cover_asset_id")
        .and_then(|x| x.as_i64())
        .unwrap_or(0);

    if cover_asset_id <= 0 {
        if mode == OutputMode::Text {
            println!("no cover found for {}", target_id);
        } else {
            print_raw(&body, mode);
        }
        return Ok(());
    }

    if mode == OutputMode::Text {
        let asset_url = format!("{}/api/assets/{}", client.get_host(), cover_asset_id);
        println!("cover_asset_id: {}", cover_asset_id);
        println!("asset_url:      {}", asset_url);
        println!();
        println!("To download:");
        println!(
            "  curl -H \"Authorization: Bearer $LANLU_TOKEN\" \"{}\" -o cover.avif",
            asset_url
        );
    } else {
        print_raw(&body, mode);
    }

    Ok(())
}

fn show_asset_url(client: &LanluApiClient, asset_id: &str, mode: OutputMode) {
    let url = format!("{}/api/assets/{}", client.get_host(), asset_id);
    if mode == OutputMode::Text {
        println!("asset_id: {}", asset_id);
        println!("asset_url: {}", url);
        println!();
        println!("To download:");
        println!(
            "  curl -H \"Authorization: Bearer $LANLU_TOKEN\" \"{}\" -o asset.avif",
            url
        );
    } else {
        let id: i64 = asset_id.parse().unwrap_or(0);
        println!(
            "{}",
            serde_json::json!({ "asset_id": id, "asset_url": url })
        );
    }
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
