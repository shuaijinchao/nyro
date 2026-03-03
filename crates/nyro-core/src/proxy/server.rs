use axum::routing::{get, post};
use axum::Router;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;

use crate::Gateway;

pub fn create_router(gateway: Gateway) -> Router {
    let proxy_routes = Router::new()
        .route("/v1/chat/completions", post(handler::openai_proxy))
        // Phase 2: Anthropic & Gemini ingress
        // .route("/v1/messages", post(handler::anthropic_proxy))
        // .route("/v1beta/models/{model}:generateContent", post(handler::gemini_proxy))
        // .route("/v1beta/models/{model}:streamGenerateContent", post(handler::gemini_stream_proxy))
        .route("/health", get(health));

    proxy_routes
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(gateway)
}

use super::handler;

async fn health() -> &'static str {
    r#"{"status":"ok"}"#
}
