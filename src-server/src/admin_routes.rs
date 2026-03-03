use axum::extract::State;
use axum::response::IntoResponse;
use axum::routing::{delete, get};
use axum::{Json, Router};
use nyro_core::db::models::*;
use nyro_core::Gateway;

pub fn create_router(gateway: Gateway, _admin_key: Option<String>) -> Router {
    let api = Router::new()
        .route("/providers", get(list_providers).post(create_provider_handler))
        .route("/providers/{id}", delete(delete_provider_handler))
        .route("/routes", get(list_routes_handler).post(create_route_handler))
        .route("/routes/{id}", delete(delete_route_handler))
        .route("/status", get(get_status))
        .with_state(gateway);

    // TODO: add bearer token auth middleware when admin_key is Some

    Router::new().nest("/api/v1", api)
}

async fn list_providers(State(gw): State<Gateway>) -> impl IntoResponse {
    match gw.admin().list_providers().await {
        Ok(providers) => Json(serde_json::json!({ "data": providers })).into_response(),
        Err(e) => Json(serde_json::json!({ "error": e.to_string() })).into_response(),
    }
}

async fn create_provider_handler(
    State(gw): State<Gateway>,
    Json(input): Json<CreateProvider>,
) -> impl IntoResponse {
    match gw.admin().create_provider(input).await {
        Ok(provider) => Json(serde_json::json!({ "data": provider })).into_response(),
        Err(e) => Json(serde_json::json!({ "error": e.to_string() })).into_response(),
    }
}

async fn delete_provider_handler(
    State(gw): State<Gateway>,
    axum::extract::Path(id): axum::extract::Path<String>,
) -> impl IntoResponse {
    match gw.admin().delete_provider(&id).await {
        Ok(()) => Json(serde_json::json!({ "ok": true })).into_response(),
        Err(e) => Json(serde_json::json!({ "error": e.to_string() })).into_response(),
    }
}

async fn list_routes_handler(State(gw): State<Gateway>) -> impl IntoResponse {
    match gw.admin().list_routes().await {
        Ok(routes) => Json(serde_json::json!({ "data": routes })).into_response(),
        Err(e) => Json(serde_json::json!({ "error": e.to_string() })).into_response(),
    }
}

async fn create_route_handler(
    State(gw): State<Gateway>,
    Json(input): Json<CreateRoute>,
) -> impl IntoResponse {
    match gw.admin().create_route(input).await {
        Ok(route) => Json(serde_json::json!({ "data": route })).into_response(),
        Err(e) => Json(serde_json::json!({ "error": e.to_string() })).into_response(),
    }
}

async fn delete_route_handler(
    State(gw): State<Gateway>,
    axum::extract::Path(id): axum::extract::Path<String>,
) -> impl IntoResponse {
    match gw.admin().delete_route(&id).await {
        Ok(()) => Json(serde_json::json!({ "ok": true })).into_response(),
        Err(e) => Json(serde_json::json!({ "error": e.to_string() })).into_response(),
    }
}

async fn get_status(State(gw): State<Gateway>) -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "running",
        "proxy_port": gw.config.proxy_port,
    }))
}
