use axum::extract::State;
use axum::response::IntoResponse;
use axum::Json;
use serde_json::Value;

use crate::Gateway;

pub async fn openai_proxy(
    State(_gateway): State<Gateway>,
    Json(_body): Json<Value>,
) -> impl IntoResponse {
    // TODO: Phase 1 — full proxy implementation
    // 1. IngressDecoder (OpenAI)
    // 2. Route matching
    // 3. EgressEncoder (target provider protocol)
    // 4. reqwest call (stream / non-stream)
    // 5. ResponseTranscoder back to OpenAI format
    Json(serde_json::json!({
        "error": "not implemented yet"
    }))
}
