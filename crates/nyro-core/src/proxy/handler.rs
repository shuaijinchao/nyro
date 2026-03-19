use std::convert::Infallible;
use std::time::Instant;

use axum::body::Body;
use axum::extract::{Path, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::Json;
use futures::StreamExt;
use reqwest::Url;
use serde_json::Value;
use tokio_stream::wrappers::ReceiverStream;

use crate::db::models::{Provider, Route};
use crate::logging::LogEntry;
use crate::protocol::gemini::decoder::GeminiDecoder;
use crate::protocol::types::*;
use crate::protocol::Protocol;
use crate::proxy::client::ProxyClient;
use crate::Gateway;

const OLLAMA_CAPABILITY_CACHE_TTL_SECS: u64 = 3600;

// ── OpenAI ingress: POST /v1/chat/completions ──

pub async fn openai_proxy(
    State(gw): State<Gateway>,
    headers: HeaderMap,
    Json(body): Json<Value>,
) -> Response {
    universal_proxy(gw, headers, body, Protocol::OpenAI).await
}

// ── OpenAI Responses API ingress: POST /v1/responses ──

pub async fn responses_proxy(
    State(gw): State<Gateway>,
    headers: HeaderMap,
    Json(body): Json<Value>,
) -> Response {
    universal_proxy(gw, headers, body, Protocol::ResponsesAPI).await
}

// ── Anthropic ingress: POST /v1/messages ──

pub async fn anthropic_proxy(
    State(gw): State<Gateway>,
    headers: HeaderMap,
    Json(body): Json<Value>,
) -> Response {
    universal_proxy(gw, headers, body, Protocol::Anthropic).await
}

// ── Gemini ingress: POST /v1beta/models/:model_action ──

pub async fn gemini_proxy(
    State(gw): State<Gateway>,
    headers: HeaderMap,
    Path(model_action): Path<String>,
    Json(body): Json<Value>,
) -> Response {
    let (model, action) = match model_action.rsplit_once(':') {
        Some((m, a)) => (m.to_string(), a.to_string()),
        None => (model_action.clone(), "generateContent".to_string()),
    };
    let is_stream = action == "streamGenerateContent";

    let decoder = GeminiDecoder;
    let internal = match decoder.decode_with_model(body, &model, is_stream) {
        Ok(r) => r,
        Err(e) => return error_response(400, &format!("invalid Gemini request: {e}")),
    };

    proxy_pipeline(gw, headers, internal, Protocol::Gemini).await
}

// ── Universal proxy pipeline ──

async fn universal_proxy(gw: Gateway, headers: HeaderMap, body: Value, ingress: Protocol) -> Response {
    let decoder = crate::protocol::get_decoder(ingress);
    let internal = match decoder.decode_request(body) {
        Ok(r) => r,
        Err(e) => return error_response(400, &format!("invalid request: {e}")),
    };

    proxy_pipeline(gw, headers, internal, ingress).await
}

async fn proxy_pipeline(
    gw: Gateway,
    headers: HeaderMap,
    mut internal: InternalRequest,
    ingress: Protocol,
) -> Response {
    let start = Instant::now();
    let request_model = internal.model.clone();
    let is_stream = internal.stream;

    let ingress_str = ingress.to_string();
    let route_protocol = ingress.route_protocol();
    let route = {
        let cache = gw.route_cache.read().await;
        cache.match_route(route_protocol, &request_model).cloned()
    };
    let route = match route {
        Some(r) => r,
        None => return error_response(404, &format!("no route for model: {request_model}")),
    };

    let auth_key = match authorize_route_access(&gw, &route, &headers).await {
        Ok(v) => v,
        Err(resp) => return resp,
    };

    let provider = match get_provider(&gw, &route.target_provider).await {
        Ok(p) => p,
        Err(e) => return error_response(502, &format!("provider error: {e}")),
    };

    let actual_model = if route.target_model.is_empty() || route.target_model == "*" {
        request_model.clone()
    } else {
        route.target_model.clone()
    };

    maybe_normalize_minimax_responses_messages(&provider, ingress, &mut internal);
    maybe_strip_ollama_tools(&gw, &provider, &actual_model, &mut internal).await;

    let egress: Protocol = provider.protocol.parse().unwrap_or(Protocol::OpenAI);

    let encoder = crate::protocol::get_encoder(egress);
    let (egress_body, extra_headers) = match encoder.encode_request(&internal) {
        Ok(r) => r,
        Err(e) => return error_response(500, &format!("encode error: {e}")),
    };

    let egress_body = override_model(egress_body, &actual_model, egress);
    let egress_path = encoder.egress_path(&actual_model, is_stream);

    let client = ProxyClient::new(gw.http_client.clone());
    let egress_str = egress.to_string();

    if is_stream {
        handle_stream(
            gw,
            client,
            &provider,
            egress,
            ingress,
            &egress_path,
            egress_body,
            extra_headers,
            &ingress_str,
            &egress_str,
            &request_model,
            &actual_model,
            auth_key.id.as_deref(),
            start,
        )
        .await
    } else {
        handle_non_stream(
            gw,
            client,
            &provider,
            egress,
            ingress,
            &egress_path,
            egress_body,
            extra_headers,
            &ingress_str,
            &egress_str,
            &request_model,
            &actual_model,
            auth_key.id.as_deref(),
            start,
        )
        .await
    }
}

fn maybe_normalize_minimax_responses_messages(
    provider: &Provider,
    ingress: Protocol,
    req: &mut InternalRequest,
) {
    // MiniMax 在部分 OpenAI 兼容路径下会拒绝 role=system。
    // Codex 使用 Responses API 时常带 instructions/developer，我们在此折叠为 user 文本，避免 2013 报错。
    if ingress != Protocol::ResponsesAPI || !is_minimax_provider(provider) {
        return;
    }

    let mut system_instructions: Vec<String> = Vec::new();
    let mut normalized_messages: Vec<InternalMessage> = Vec::with_capacity(req.messages.len());

    for msg in req.messages.drain(..) {
        if msg.role == Role::System {
            let text = msg.content.as_text();
            if !text.trim().is_empty() {
                system_instructions.push(text);
            }
            continue;
        }
        normalized_messages.push(msg);
    }

    if system_instructions.is_empty() {
        req.messages = normalized_messages;
        return;
    }

    let merged_instructions = format!(
        "[System Instructions]\n{}",
        system_instructions.join("\n\n")
    );

    if let Some(first_user) = normalized_messages.iter_mut().find(|m| m.role == Role::User) {
        match &mut first_user.content {
            MessageContent::Text(text) => {
                if text.trim().is_empty() {
                    *text = merged_instructions;
                } else {
                    *text = format!("{merged_instructions}\n\n{text}");
                }
            }
            MessageContent::Blocks(blocks) => {
                blocks.insert(
                    0,
                    ContentBlock::Text {
                        text: format!("{merged_instructions}\n\n"),
                    },
                );
            }
        }
    } else {
        normalized_messages.insert(
            0,
            InternalMessage {
                role: Role::User,
                content: MessageContent::Text(merged_instructions),
                tool_calls: None,
                tool_call_id: None,
            },
        );
    }

    req.messages = normalized_messages;
}

async fn maybe_strip_ollama_tools(
    gw: &Gateway,
    provider: &Provider,
    model_for_capability_check: &str,
    req: &mut InternalRequest,
) {
    if !is_ollama_provider(provider) {
        return;
    }

    if req.tools.is_none() && req.tool_choice.is_none() {
        return;
    }

    let caps = match get_ollama_capabilities(gw, provider, model_for_capability_check).await {
        Ok(v) => v,
        Err(e) => {
            tracing::warn!(
                "failed to fetch capabilities for model {}, skipping tools check: {}",
                model_for_capability_check,
                e
            );
            return;
        }
    };

    let supports_tools = caps.iter().any(|c| c == "tools");
    if !supports_tools {
        tracing::warn!(
            "tools stripped for model {} (tools not supported, capabilities: {:?})",
            model_for_capability_check,
            caps
        );
        req.tools = None;
        req.tool_choice = None;
        req.extra.remove("tools");
        req.extra.remove("tool_choice");
    }
}

async fn get_ollama_capabilities(
    gw: &Gateway,
    provider: &Provider,
    model: &str,
) -> anyhow::Result<Vec<String>> {
    let ttl = std::time::Duration::from_secs(OLLAMA_CAPABILITY_CACHE_TTL_SECS);
    if let Some(cached) = gw
        .get_ollama_capabilities_cached(&provider.id, model, ttl)
        .await
    {
        return Ok(cached);
    }

    let caps = fetch_ollama_capabilities(&gw.http_client, &provider.base_url, model).await?;
    gw.set_ollama_capabilities_cache(&provider.id, model, caps.clone())
        .await;
    Ok(caps)
}

async fn fetch_ollama_capabilities(
    http: &reqwest::Client,
    base_url: &str,
    model: &str,
) -> anyhow::Result<Vec<String>> {
    let url = build_ollama_show_url(base_url)?;

    let resp = http
        .post(url)
        .json(&serde_json::json!({ "name": model }))
        .timeout(std::time::Duration::from_secs(5))
        .send()
        .await?;

    if !resp.status().is_success() {
        anyhow::bail!("ollama /api/show returned status {}", resp.status());
    }

    let json: Value = resp.json().await?;
    let caps = json
        .get("capabilities")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|c| c.as_str().map(ToString::to_string))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    Ok(caps)
}

fn build_ollama_show_url(base_url: &str) -> anyhow::Result<Url> {
    let mut url = Url::parse(base_url)?;
    let raw_path = url.path().trim_end_matches('/');
    let path = if raw_path.is_empty() {
        "/api/show".to_string()
    } else if raw_path.ends_with("/v1") {
        let prefix = raw_path.trim_end_matches("/v1");
        if prefix.is_empty() {
            "/api/show".to_string()
        } else {
            format!("{prefix}/api/show")
        }
    } else {
        format!("{raw_path}/api/show")
    };
    url.set_path(&path);
    url.set_query(None);
    Ok(url)
}

fn is_ollama_provider(provider: &Provider) -> bool {
    provider
        .vendor
        .as_deref()
        .is_some_and(|v| v.eq_ignore_ascii_case("ollama"))
}

fn is_minimax_provider(provider: &Provider) -> bool {
    if provider
        .vendor
        .as_deref()
        .is_some_and(|v| v.eq_ignore_ascii_case("minimax"))
    {
        return true;
    }

    provider.base_url.contains("minimax")
}

#[allow(clippy::too_many_arguments)]
async fn handle_non_stream(
    gw: Gateway,
    client: ProxyClient,
    provider: &Provider,
    egress: Protocol,
    ingress: Protocol,
    path: &str,
    body: Value,
    extra_headers: reqwest::header::HeaderMap,
    ingress_str: &str,
    egress_str: &str,
    request_model: &str,
    actual_model: &str,
    api_key_id: Option<&str>,
    start: Instant,
) -> Response {
    let (resp, status) = match client
        .call_non_stream(
            &provider.base_url,
            path,
            &provider.api_key,
            egress,
            body,
            extra_headers,
        )
        .await
    {
        Ok(r) => r,
        Err(e) => {
            emit_log(
                &gw, ingress_str, egress_str, request_model, actual_model,
                api_key_id,
                &provider.name, 502, start.elapsed().as_millis() as f64,
                TokenUsage::default(), false, false,
                Some(e.to_string()), None, None,
            );
            return error_response(502, &format!("upstream error: {e}"));
        }
    };

    if status >= 400 {
        let preview = serde_json::to_string(&resp).ok().map(|s| s.chars().take(500).collect());
        emit_log(
            &gw, ingress_str, egress_str, request_model, actual_model,
            api_key_id,
            &provider.name, status as i32, start.elapsed().as_millis() as f64,
            TokenUsage::default(), false, false,
            preview.clone(), None, None,
        );
        return (
            StatusCode::from_u16(status).unwrap_or(StatusCode::BAD_GATEWAY),
            Json(resp),
        )
            .into_response();
    }

    let parser = crate::protocol::get_response_parser(egress);
    let formatter = crate::protocol::get_response_formatter(ingress);

    let internal_resp = match parser.parse_response(resp) {
        Ok(r) => r,
        Err(e) => return error_response(500, &format!("parse error: {e}")),
    };

    let is_tool = !internal_resp.tool_calls.is_empty();
    let usage = internal_resp.usage.clone();
    let output = formatter.format_response(&internal_resp);

    let response_preview = serde_json::to_string(&output)
        .ok()
        .map(|s| s.chars().take(500).collect());

    emit_log(
        &gw, ingress_str, egress_str, request_model, actual_model,
        api_key_id,
        &provider.name, status as i32, start.elapsed().as_millis() as f64,
        usage, false, is_tool, None, None, response_preview,
    );

    (
        StatusCode::from_u16(status).unwrap_or(StatusCode::OK),
        Json(output),
    )
        .into_response()
}

#[allow(clippy::too_many_arguments)]
async fn handle_stream(
    gw: Gateway,
    client: ProxyClient,
    provider: &Provider,
    egress: Protocol,
    ingress: Protocol,
    path: &str,
    body: Value,
    extra_headers: reqwest::header::HeaderMap,
    ingress_str: &str,
    egress_str: &str,
    request_model: &str,
    actual_model: &str,
    api_key_id: Option<&str>,
    start: Instant,
) -> Response {
    let (resp, status) = match client
        .call_stream(
            &provider.base_url,
            path,
            &provider.api_key,
            egress,
            body,
            extra_headers,
        )
        .await
    {
        Ok(r) => r,
        Err(e) => {
            emit_log(
                &gw, ingress_str, egress_str, request_model, actual_model,
                api_key_id,
                &provider.name, 502, start.elapsed().as_millis() as f64,
                TokenUsage::default(), true, false,
                Some(e.to_string()), None, None,
            );
            return error_response(502, &format!("upstream error: {e}"));
        }
    };

    if status >= 400 {
        let err_body: Value = resp
            .json()
            .await
            .unwrap_or_else(|_| serde_json::json!({"error": {"message": "upstream error"}}));
        emit_log(
            &gw, ingress_str, egress_str, request_model, actual_model,
            api_key_id,
            &provider.name, status as i32, start.elapsed().as_millis() as f64,
            TokenUsage::default(), true, false,
            Some(err_body.to_string()), None, None,
        );
        return (
            StatusCode::from_u16(status).unwrap_or(StatusCode::BAD_GATEWAY),
            Json(err_body),
        )
            .into_response();
    }

    let mut stream_parser = crate::protocol::get_stream_parser(egress);
    let mut stream_formatter = crate::protocol::get_stream_formatter(ingress);

    let mut byte_stream = resp.bytes_stream();
    let (tx, rx) = tokio::sync::mpsc::channel::<Result<String, Infallible>>(64);

    let gw_log = gw.clone();
    let provider_name = provider.name.clone();
    let ingress_s = ingress_str.to_string();
    let egress_s = egress_str.to_string();
    let req_model = request_model.to_string();
    let act_model = actual_model.to_string();
    let key_id = api_key_id.map(ToString::to_string);

    tokio::spawn(async move {
        while let Some(chunk) = byte_stream.next().await {
            let bytes = match chunk {
                Ok(b) => b,
                Err(_) => break,
            };
            let text = String::from_utf8_lossy(&bytes);
            if let Ok(deltas) = stream_parser.parse_chunk(&text) {
                let events = stream_formatter.format_deltas(&deltas);
                for ev in events {
                    if tx.send(Ok(ev.to_sse_string())).await.is_err() {
                        return;
                    }
                }
            }
        }

        if let Ok(deltas) = stream_parser.finish() {
            let events = stream_formatter.format_deltas(&deltas);
            for ev in events {
                let _ = tx.send(Ok(ev.to_sse_string())).await;
            }
        }

        let done_events = stream_formatter.format_done();
        for ev in done_events {
            let _ = tx.send(Ok(ev.to_sse_string())).await;
        }

        let usage = stream_formatter.usage();
        emit_log(
            &gw_log, &ingress_s, &egress_s, &req_model, &act_model,
            key_id.as_deref(),
            &provider_name, 200, start.elapsed().as_millis() as f64,
            usage, true, false, None, None, None,
        );
    });

    let stream = ReceiverStream::new(rx);
    let body = Body::from_stream(stream);

    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "text/event-stream")
        .header(header::CACHE_CONTROL, "no-cache")
        .header(header::CONNECTION, "keep-alive")
        .body(body)
        .unwrap()
}

// ── Helpers ──

struct AuthenticatedKey {
    id: Option<String>,
}

async fn authorize_route_access(gw: &Gateway, route: &Route, headers: &HeaderMap) -> Result<AuthenticatedKey, Response> {
    if !route.access_control {
        return Ok(AuthenticatedKey { id: None });
    }

    let Some(raw_key) = extract_api_key(headers) else {
        return Err(error_response(401, "missing api key"));
    };

    let key_row = sqlx::query_as::<_, (String, String, Option<String>, Option<i32>, Option<i32>, Option<i32>, Option<i32>)>(
        "SELECT id, status, expires_at, rpm, rpd, tpm, tpd FROM api_keys WHERE key = ?",
    )
    .bind(&raw_key)
    .fetch_optional(&gw.db)
    .await
    .map_err(|e| error_response(500, &format!("auth db error: {e}")))?;

    let Some((api_key_id, status, expires_at, rpm, rpd, tpm, tpd)) = key_row else {
        return Err(error_response(401, "invalid api key"));
    };

    if status != "active" {
        return Err(error_response(403, "api key revoked"));
    }

    if let Some(expires) = expires_at.as_ref() {
        let is_expired = sqlx::query_scalar::<_, i64>(
            "SELECT CASE WHEN datetime(?) <= datetime('now') THEN 1 ELSE 0 END",
        )
        .bind(expires)
        .fetch_one(&gw.db)
        .await
        .map(|v| v > 0)
        .unwrap_or(false);
        if is_expired {
            return Err(error_response(403, "api key expired"));
        }
    }

    let allowed = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM api_key_routes WHERE api_key_id = ? AND route_id = ?",
    )
    .bind(&api_key_id)
    .bind(&route.id)
    .fetch_one(&gw.db)
    .await
    .map_err(|e| error_response(500, &format!("auth db error: {e}")))?;
    if allowed == 0 {
        return Err(error_response(403, "api key not allowed for this route"));
    }

    if let Some(limit) = rpm.filter(|v| *v > 0) {
        let req_count = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM request_logs WHERE api_key_id = ? AND created_at >= datetime('now', '-1 minute')",
        )
        .bind(&api_key_id)
        .fetch_one(&gw.db)
        .await
        .map_err(|e| error_response(500, &format!("quota db error: {e}")))?;
        if req_count >= i64::from(limit) {
            return Err(error_response(429, "api key rpm quota exceeded"));
        }
    }

    if let Some(limit) = rpd.filter(|v| *v > 0) {
        let req_count = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM request_logs WHERE api_key_id = ? AND created_at >= datetime('now', '-1 day')",
        )
        .bind(&api_key_id)
        .fetch_one(&gw.db)
        .await
        .map_err(|e| error_response(500, &format!("quota db error: {e}")))?;
        if req_count >= i64::from(limit) {
            return Err(error_response(429, "api key rpd quota exceeded"));
        }
    }

    if let Some(limit) = tpm.filter(|v| *v > 0) {
        let token_count = sqlx::query_scalar::<_, i64>(
            "SELECT COALESCE(SUM(input_tokens + output_tokens), 0) FROM request_logs WHERE api_key_id = ? AND created_at >= datetime('now', '-1 minute')",
        )
        .bind(&api_key_id)
        .fetch_one(&gw.db)
        .await
        .map_err(|e| error_response(500, &format!("quota db error: {e}")))?;
        if token_count >= i64::from(limit) {
            return Err(error_response(429, "api key tpm quota exceeded"));
        }
    }

    if let Some(limit) = tpd.filter(|v| *v > 0) {
        let token_count = sqlx::query_scalar::<_, i64>(
            "SELECT COALESCE(SUM(input_tokens + output_tokens), 0) FROM request_logs WHERE api_key_id = ? AND created_at >= datetime('now', '-1 day')",
        )
        .bind(&api_key_id)
        .fetch_one(&gw.db)
        .await
        .map_err(|e| error_response(500, &format!("quota db error: {e}")))?;
        if token_count >= i64::from(limit) {
            return Err(error_response(429, "api key tpd quota exceeded"));
        }
    }

    Ok(AuthenticatedKey {
        id: Some(api_key_id),
    })
}

fn extract_api_key(headers: &HeaderMap) -> Option<String> {
    if let Some(value) = headers.get(header::AUTHORIZATION).and_then(|v| v.to_str().ok()) {
        if let Some(token) = value.strip_prefix("Bearer ") {
            let token = token.trim();
            if !token.is_empty() {
                return Some(token.to_string());
            }
        }
    }

    headers
        .get("x-api-key")
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .map(ToString::to_string)
}

async fn get_provider(gw: &Gateway, id: &str) -> anyhow::Result<Provider> {
    sqlx::query_as::<_, Provider>(
        "SELECT id, name, vendor, protocol, base_url, preset_key, COALESCE(channel, region) AS channel, models_endpoint, COALESCE(models_source, models_endpoint) AS models_source, capabilities_source, static_models, api_key, last_test_success, last_test_at, is_active, created_at, updated_at \
         FROM providers WHERE id = ? AND is_active = 1",
    )
    .bind(id)
    .fetch_optional(&gw.db)
    .await?
    .ok_or_else(|| anyhow::anyhow!("provider not found or inactive: {id}"))
}

fn override_model(mut body: Value, model: &str, protocol: Protocol) -> Value {
    match protocol {
        Protocol::Gemini => body,
        _ => {
            if let Some(obj) = body.as_object_mut() {
                obj.insert("model".into(), Value::String(model.to_string()));
            }
            body
        }
    }
}

fn error_response(status: u16, message: &str) -> Response {
    let code = StatusCode::from_u16(status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    (
        code,
        Json(serde_json::json!({
            "error": {
                "message": message,
                "type": "gateway_error",
                "code": status
            }
        })),
    )
        .into_response()
}

fn emit_log(
    gw: &Gateway,
    ingress: &str,
    egress: &str,
    request_model: &str,
    actual_model: &str,
    api_key_id: Option<&str>,
    provider_name: &str,
    status_code: i32,
    duration_ms: f64,
    usage: TokenUsage,
    is_stream: bool,
    is_tool_call: bool,
    error_message: Option<String>,
    request_preview: Option<String>,
    response_preview: Option<String>,
) {
    let _ = gw.log_tx.try_send(LogEntry {
        api_key_id: api_key_id.map(ToString::to_string),
        ingress_protocol: ingress.to_string(),
        egress_protocol: egress.to_string(),
        request_model: request_model.to_string(),
        actual_model: actual_model.to_string(),
        provider_name: provider_name.to_string(),
        status_code,
        duration_ms,
        usage,
        is_stream,
        is_tool_call,
        error_message,
        request_preview,
        response_preview,
    });
}
