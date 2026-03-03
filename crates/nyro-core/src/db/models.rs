use serde::{Deserialize, Serialize};
use sqlx::FromRow;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Provider {
    pub id: String,
    pub name: String,
    pub protocol: String,
    pub base_url: String,
    #[serde(skip_serializing)]
    pub api_key: String,
    pub is_active: bool,
    pub priority: i32,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Route {
    pub id: String,
    pub name: String,
    pub match_pattern: String,
    pub target_provider: String,
    pub target_model: String,
    pub fallback_provider: Option<String>,
    pub fallback_model: Option<String>,
    pub is_active: bool,
    pub priority: i32,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct RequestLog {
    pub id: String,
    pub created_at: String,
    pub ingress_protocol: Option<String>,
    pub egress_protocol: Option<String>,
    pub request_model: Option<String>,
    pub actual_model: Option<String>,
    pub provider_name: Option<String>,
    pub status_code: Option<i32>,
    pub duration_ms: Option<f64>,
    pub input_tokens: i32,
    pub output_tokens: i32,
    pub is_stream: bool,
    pub is_tool_call: bool,
    pub error_message: Option<String>,
    pub request_preview: Option<String>,
    pub response_preview: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateProvider {
    pub name: String,
    pub protocol: String,
    pub base_url: String,
    pub api_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateProvider {
    pub name: Option<String>,
    pub protocol: Option<String>,
    pub base_url: Option<String>,
    pub api_key: Option<String>,
    pub is_active: Option<bool>,
    pub priority: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateRoute {
    pub name: String,
    pub match_pattern: String,
    pub target_provider: String,
    pub target_model: String,
    pub fallback_provider: Option<String>,
    pub fallback_model: Option<String>,
}
