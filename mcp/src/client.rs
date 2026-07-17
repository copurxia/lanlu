use crate::utils::url_encode;
use reqwest::Client;
use std::collections::HashMap;

pub struct LanluApiClient {
    host: String,
    token: String,
    no_proxy: bool,
    inner: Client,
}

impl LanluApiClient {
    pub fn new(host: String, token: String, no_proxy: bool) -> Self {
        let inner = Client::builder()
            .no_proxy()
            .build()
            .expect("failed to build reqwest Client");
        Self {
            host: host.trim_end_matches('/').to_string(),
            token,
            no_proxy,
            inner,
        }
    }

    pub fn get_host(&self) -> &str {
        &self.host
    }

    fn build_url(&self, path: &str, query: &HashMap<&str, String>) -> String {
        let path = if path.starts_with('/') {
            path.to_string()
        } else {
            format!("/{}", path)
        };
        let base = format!("{}{}", self.host, path);
        if query.is_empty() {
            return base;
        }
        let qs: Vec<String> = query
            .iter()
            .map(|(k, v)| format!("{}={}", url_encode(k), url_encode(v)))
            .collect();
        format!("{}?{}", base, qs.join("&"))
    }

    fn headers(&self) -> reqwest::header::HeaderMap {
        use reqwest::header::{HeaderMap, HeaderValue, ACCEPT, AUTHORIZATION};
        let mut h = HeaderMap::new();
        h.insert(
            AUTHORIZATION,
            HeaderValue::from_str(&format!("Bearer {}", self.token)).unwrap(),
        );
        h.insert(ACCEPT, HeaderValue::from_static("application/json"));
        if self.no_proxy {
            h.insert(
                reqwest::header::HeaderName::from_static("x-no-proxy"),
                HeaderValue::from_static("1"),
            );
        }
        h
    }

    pub async fn get(&self, path: &str, query: HashMap<&str, String>) -> Result<String, String> {
        let url = self.build_url(path, &query);
        let resp = self
            .inner
            .get(&url)
            .headers(self.headers())
            .send()
            .await
            .map_err(|e| format!("HTTP request failed: {}", e))?;
        let status = resp.status();
        let body = resp
            .text()
            .await
            .map_err(|e| format!("read response failed: {}", e))?;
        if !status.is_success() {
            return Err(format!("HTTP {}: {}", status.as_u16(), body));
        }
        Ok(body)
    }

    pub async fn post(&self, path: &str, body: &str) -> Result<String, String> {
        let url = self.build_url(path, &HashMap::new());
        let resp = self
            .inner
            .post(&url)
            .headers(self.headers())
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .body(body.to_owned())
            .send()
            .await
            .map_err(|e| format!("HTTP request failed: {}", e))?;
        let status = resp.status();
        let body = resp
            .text()
            .await
            .map_err(|e| format!("read response failed: {}", e))?;
        if !status.is_success() {
            return Err(format!("HTTP {}: {}", status.as_u16(), body));
        }
        Ok(body)
    }

    pub async fn put(&self, path: &str, body: &str) -> Result<String, String> {
        let url = self.build_url(path, &HashMap::new());
        let resp = self
            .inner
            .put(&url)
            .headers(self.headers())
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .body(body.to_owned())
            .send()
            .await
            .map_err(|e| format!("HTTP request failed: {}", e))?;
        let status = resp.status();
        let body = resp
            .text()
            .await
            .map_err(|e| format!("read response failed: {}", e))?;
        if !status.is_success() {
            return Err(format!("HTTP {}: {}", status.as_u16(), body));
        }
        Ok(body)
    }

    pub async fn put_bytes(
        &self,
        path: &str,
        query: HashMap<&str, String>,
        bytes: Vec<u8>,
    ) -> Result<String, String> {
        let url = self.build_url(path, &query);
        let resp = self
            .inner
            .put(&url)
            .headers(self.headers())
            .header(reqwest::header::CONTENT_TYPE, "application/octet-stream")
            .body(bytes)
            .send()
            .await
            .map_err(|e| format!("HTTP request failed: {}", e))?;
        let status = resp.status();
        let body = resp
            .text()
            .await
            .map_err(|e| format!("read response failed: {}", e))?;
        if !status.is_success() {
            return Err(format!("HTTP {}: {}", status.as_u16(), body));
        }
        Ok(body)
    }
}
