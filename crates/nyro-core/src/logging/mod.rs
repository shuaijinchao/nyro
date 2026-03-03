use sqlx::SqlitePool;
use tokio::sync::mpsc;

use crate::protocol::types::TokenUsage;

#[derive(Debug, Clone)]
pub struct LogEntry {
    pub ingress_protocol: String,
    pub egress_protocol: String,
    pub request_model: String,
    pub actual_model: String,
    pub provider_name: String,
    pub status_code: i32,
    pub duration_ms: f64,
    pub usage: TokenUsage,
    pub is_stream: bool,
    pub is_tool_call: bool,
    pub error_message: Option<String>,
    pub request_preview: Option<String>,
    pub response_preview: Option<String>,
}

pub async fn run_collector(mut rx: mpsc::Receiver<LogEntry>, db: SqlitePool) {
    let mut buffer: Vec<LogEntry> = Vec::with_capacity(64);
    let mut interval = tokio::time::interval(std::time::Duration::from_secs(2));

    loop {
        tokio::select! {
            Some(entry) = rx.recv() => {
                buffer.push(entry);
                if buffer.len() >= 64 {
                    flush(&db, &mut buffer).await;
                }
            }
            _ = interval.tick() => {
                if !buffer.is_empty() {
                    flush(&db, &mut buffer).await;
                }
            }
        }
    }
}

async fn flush(db: &SqlitePool, buffer: &mut Vec<LogEntry>) {
    for entry in buffer.drain(..) {
        let id = uuid::Uuid::new_v4().to_string();
        let _ = sqlx::query(
            r#"INSERT INTO request_logs
                (id, ingress_protocol, egress_protocol, request_model, actual_model,
                 provider_name, status_code, duration_ms, input_tokens, output_tokens,
                 is_stream, is_tool_call, error_message, request_preview, response_preview)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"#,
        )
        .bind(&id)
        .bind(&entry.ingress_protocol)
        .bind(&entry.egress_protocol)
        .bind(&entry.request_model)
        .bind(&entry.actual_model)
        .bind(&entry.provider_name)
        .bind(entry.status_code)
        .bind(entry.duration_ms)
        .bind(entry.usage.input_tokens as i32)
        .bind(entry.usage.output_tokens as i32)
        .bind(entry.is_stream as i32)
        .bind(entry.is_tool_call as i32)
        .bind(&entry.error_message)
        .bind(&entry.request_preview)
        .bind(&entry.response_preview)
        .execute(db)
        .await;
    }
}
