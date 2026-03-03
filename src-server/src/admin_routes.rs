use axum::extract::{Path, Query, State};
use axum::response::IntoResponse;
use axum::routing::{get, put};
use axum::{Json, Router};
use nyro_core::db::models::*;
use nyro_core::Gateway;
use serde::Deserialize;

pub fn create_router(gateway: Gateway, _admin_key: Option<String>) -> Router {
    let api = Router::new()
        // Providers
        .route("/providers", get(list_providers).post(create_provider_handler))
        .route(
            "/providers/{id}",
            get(get_provider_handler)
                .put(update_provider_handler)
                .delete(delete_provider_handler),
        )
        .route("/providers/{id}/test", get(test_provider_handler))
        // Routes
        .route("/routes", get(list_routes_handler).post(create_route_handler))
        .route(
            "/routes/{id}",
            put(update_route_handler).delete(delete_route_handler),
        )
        // Logs
        .route("/logs", get(query_logs_handler))
        // Stats
        .route("/stats/overview", get(stats_overview))
        .route("/stats/hourly", get(stats_hourly))
        .route("/stats/models", get(stats_by_model))
        .route("/stats/providers", get(stats_by_provider))
        // Settings
        .route("/settings/{key}", get(get_setting).put(set_setting))
        // Status
        .route("/status", get(get_status))
        .with_state(gateway);

    Router::new().nest("/api/v1", api)
}

// ── Providers ──

async fn list_providers(State(gw): State<Gateway>) -> impl IntoResponse {
    match gw.admin().list_providers().await {
        Ok(v) => Json(serde_json::json!({ "data": v })).into_response(),
        Err(e) => err(e),
    }
}

async fn get_provider_handler(
    State(gw): State<Gateway>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    match gw.admin().get_provider(&id).await {
        Ok(v) => Json(serde_json::json!({ "data": v })).into_response(),
        Err(e) => err(e),
    }
}

async fn create_provider_handler(
    State(gw): State<Gateway>,
    Json(input): Json<CreateProvider>,
) -> impl IntoResponse {
    match gw.admin().create_provider(input).await {
        Ok(v) => Json(serde_json::json!({ "data": v })).into_response(),
        Err(e) => err(e),
    }
}

async fn update_provider_handler(
    State(gw): State<Gateway>,
    Path(id): Path<String>,
    Json(input): Json<UpdateProvider>,
) -> impl IntoResponse {
    match gw.admin().update_provider(&id, input).await {
        Ok(v) => Json(serde_json::json!({ "data": v })).into_response(),
        Err(e) => err(e),
    }
}

async fn delete_provider_handler(
    State(gw): State<Gateway>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    match gw.admin().delete_provider(&id).await {
        Ok(()) => Json(serde_json::json!({ "ok": true })).into_response(),
        Err(e) => err(e),
    }
}

async fn test_provider_handler(
    State(gw): State<Gateway>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    match gw.admin().test_provider(&id).await {
        Ok(v) => Json(serde_json::json!({ "data": v })).into_response(),
        Err(e) => err(e),
    }
}

// ── Routes ──

async fn list_routes_handler(State(gw): State<Gateway>) -> impl IntoResponse {
    match gw.admin().list_routes().await {
        Ok(v) => Json(serde_json::json!({ "data": v })).into_response(),
        Err(e) => err(e),
    }
}

async fn create_route_handler(
    State(gw): State<Gateway>,
    Json(input): Json<CreateRoute>,
) -> impl IntoResponse {
    match gw.admin().create_route(input).await {
        Ok(v) => Json(serde_json::json!({ "data": v })).into_response(),
        Err(e) => err(e),
    }
}

async fn update_route_handler(
    State(gw): State<Gateway>,
    Path(id): Path<String>,
    Json(input): Json<UpdateRoute>,
) -> impl IntoResponse {
    match gw.admin().update_route(&id, input).await {
        Ok(v) => Json(serde_json::json!({ "data": v })).into_response(),
        Err(e) => err(e),
    }
}

async fn delete_route_handler(
    State(gw): State<Gateway>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    match gw.admin().delete_route(&id).await {
        Ok(()) => Json(serde_json::json!({ "ok": true })).into_response(),
        Err(e) => err(e),
    }
}

// ── Logs ──

#[derive(Deserialize, Default)]
struct LogQueryParams {
    limit: Option<i64>,
    offset: Option<i64>,
    provider: Option<String>,
    model: Option<String>,
    status_min: Option<i32>,
    status_max: Option<i32>,
}

async fn query_logs_handler(
    State(gw): State<Gateway>,
    Query(params): Query<LogQueryParams>,
) -> impl IntoResponse {
    let q = LogQuery {
        limit: params.limit,
        offset: params.offset,
        provider: params.provider,
        model: params.model,
        status_min: params.status_min,
        status_max: params.status_max,
    };
    match gw.admin().query_logs(q).await {
        Ok(v) => Json(serde_json::json!({ "data": v })).into_response(),
        Err(e) => err(e),
    }
}

// ── Stats ──

async fn stats_overview(State(gw): State<Gateway>) -> impl IntoResponse {
    match gw.admin().get_stats_overview().await {
        Ok(v) => Json(serde_json::json!({ "data": v })).into_response(),
        Err(e) => err(e),
    }
}

#[derive(Deserialize)]
struct HourlyParams {
    #[serde(default = "default_hours")]
    hours: i32,
}

fn default_hours() -> i32 {
    24
}

async fn stats_hourly(
    State(gw): State<Gateway>,
    Query(params): Query<HourlyParams>,
) -> impl IntoResponse {
    match gw.admin().get_stats_hourly(params.hours).await {
        Ok(v) => Json(serde_json::json!({ "data": v })).into_response(),
        Err(e) => err(e),
    }
}

async fn stats_by_model(State(gw): State<Gateway>) -> impl IntoResponse {
    match gw.admin().get_stats_by_model().await {
        Ok(v) => Json(serde_json::json!({ "data": v })).into_response(),
        Err(e) => err(e),
    }
}

async fn stats_by_provider(State(gw): State<Gateway>) -> impl IntoResponse {
    match gw.admin().get_stats_by_provider().await {
        Ok(v) => Json(serde_json::json!({ "data": v })).into_response(),
        Err(e) => err(e),
    }
}

// ── Settings ──

async fn get_setting(
    State(gw): State<Gateway>,
    Path(key): Path<String>,
) -> impl IntoResponse {
    match gw.admin().get_setting(&key).await {
        Ok(v) => Json(serde_json::json!({ "data": v })).into_response(),
        Err(e) => err(e),
    }
}

#[derive(Deserialize)]
struct SettingBody {
    value: String,
}

async fn set_setting(
    State(gw): State<Gateway>,
    Path(key): Path<String>,
    Json(body): Json<SettingBody>,
) -> impl IntoResponse {
    match gw.admin().set_setting(&key, &body.value).await {
        Ok(()) => Json(serde_json::json!({ "ok": true })).into_response(),
        Err(e) => err(e),
    }
}

// ── Status ──

async fn get_status(State(gw): State<Gateway>) -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "running",
        "proxy_port": gw.config.proxy_port,
    }))
}

fn err(e: anyhow::Error) -> axum::response::Response {
    Json(serde_json::json!({ "error": e.to_string() })).into_response()
}
