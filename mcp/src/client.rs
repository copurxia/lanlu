use crate::utils::url_encode;
use reqwest::Client;
use std::collections::HashMap;

/// Validate that `LANLU_TOKEN` can be used as a Bearer header value.
///
/// Returns `Err` for empty tokens or tokens containing bytes that are illegal
/// in an HTTP header field value (e.g. CR/LF), which would otherwise panic
/// when the header is constructed.
pub fn validate_token(token: &str) -> Result<(), String> {
    if token.is_empty() {
        return Err("LANLU_TOKEN must not be empty".to_string());
    }
    reqwest::header::HeaderValue::from_str(&format!("Bearer {}", token))
        .map(|_| ())
        .map_err(|e| format!("LANLU_TOKEN contains invalid characters: {}", e))
}

pub struct LanluApiClient {
    host: String,
    token: String,
    no_proxy: bool,
    inner: Client,
}

impl LanluApiClient {
    pub fn new(host: String, token: String, no_proxy: bool) -> Self {
        let mut builder = Client::builder();
        // Only bypass system/http proxies when the caller explicitly opted in
        // via LANLU_NO_PROXY; otherwise reqwest honours http_proxy/https_proxy.
        if no_proxy {
            builder = builder.no_proxy();
        }
        let inner = builder
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_token_accepts_plain_ascii() {
        assert!(validate_token("good-token-123").is_ok());
    }

    #[test]
    fn validate_token_rejects_empty() {
        assert!(validate_token("").is_err());
    }

    #[test]
    fn validate_token_rejects_newline_bytes() {
        assert!(validate_token("bad\nvalue").is_err());
        assert!(validate_token("bad\rvalue").is_err());
    }

    #[test]
    fn validate_token_rejects_nul_byte() {
        assert!(validate_token("bad\0value").is_err());
    }
}
