use anyhow::Result;
use bytes::Bytes;
use futures::Stream;
use reqwest::header::HeaderMap;
use serde_json::Value;

pub struct ProxyClient {
    http: reqwest::Client,
}

impl ProxyClient {
    pub fn new(http: reqwest::Client) -> Self {
        Self { http }
    }

    pub async fn call(
        &self,
        base_url: &str,
        path: &str,
        api_key: &str,
        body: Value,
        extra_headers: HeaderMap,
    ) -> Result<Value> {
        let url = format!("{}{}", base_url.trim_end_matches('/'), path);
        let resp = self
            .http
            .post(&url)
            .header("Authorization", format!("Bearer {api_key}"))
            .headers(extra_headers)
            .json(&body)
            .send()
            .await?
            .error_for_status()?;
        Ok(resp.json().await?)
    }

    pub async fn call_stream(
        &self,
        base_url: &str,
        path: &str,
        api_key: &str,
        body: Value,
        extra_headers: HeaderMap,
    ) -> Result<impl Stream<Item = Result<Bytes, reqwest::Error>>> {
        let url = format!("{}{}", base_url.trim_end_matches('/'), path);
        let resp = self
            .http
            .post(&url)
            .header("Authorization", format!("Bearer {api_key}"))
            .headers(extra_headers)
            .json(&body)
            .send()
            .await?
            .error_for_status()?;
        Ok(resp.bytes_stream())
    }
}
