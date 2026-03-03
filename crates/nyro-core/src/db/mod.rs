pub mod models;

use std::path::Path;

use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::SqlitePool;

pub async fn init_pool(data_dir: &Path) -> anyhow::Result<SqlitePool> {
    std::fs::create_dir_all(data_dir)?;
    let db_path = data_dir.join("gateway.db");

    let options = SqliteConnectOptions::new()
        .filename(&db_path)
        .create_if_missing(true)
        .journal_mode(sqlx::sqlite::SqliteJournalMode::Wal)
        .busy_timeout(std::time::Duration::from_secs(5));

    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect_with(options)
        .await?;

    Ok(pool)
}

pub async fn migrate(pool: &SqlitePool) -> anyhow::Result<()> {
    sqlx::raw_sql(INIT_SQL).execute(pool).await?;
    Ok(())
}

const INIT_SQL: &str = r#"
CREATE TABLE IF NOT EXISTS providers (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    protocol    TEXT NOT NULL,
    base_url    TEXT NOT NULL,
    api_key     TEXT NOT NULL,
    is_active   INTEGER DEFAULT 1,
    priority    INTEGER DEFAULT 0,
    created_at  TEXT DEFAULT (datetime('now')),
    updated_at  TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS routes (
    id                TEXT PRIMARY KEY,
    name              TEXT NOT NULL,
    match_pattern     TEXT NOT NULL,
    target_provider   TEXT NOT NULL REFERENCES providers(id),
    target_model      TEXT NOT NULL,
    fallback_provider TEXT REFERENCES providers(id),
    fallback_model    TEXT,
    is_active         INTEGER DEFAULT 1,
    priority          INTEGER DEFAULT 0,
    created_at        TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS request_logs (
    id                TEXT PRIMARY KEY,
    created_at        TEXT DEFAULT (datetime('now')),
    ingress_protocol  TEXT,
    egress_protocol   TEXT,
    request_model     TEXT,
    actual_model      TEXT,
    provider_name     TEXT,
    status_code       INTEGER,
    duration_ms       REAL,
    input_tokens      INTEGER DEFAULT 0,
    output_tokens     INTEGER DEFAULT 0,
    is_stream         INTEGER DEFAULT 0,
    is_tool_call      INTEGER DEFAULT 0,
    error_message     TEXT,
    request_preview   TEXT,
    response_preview  TEXT
);

CREATE INDEX IF NOT EXISTS idx_logs_created_at ON request_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_logs_provider ON request_logs(provider_name);
CREATE INDEX IF NOT EXISTS idx_logs_status ON request_logs(status_code);
CREATE INDEX IF NOT EXISTS idx_logs_model ON request_logs(actual_model);

CREATE TABLE IF NOT EXISTS models (
    id          TEXT PRIMARY KEY,
    provider_id TEXT NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
    model_name  TEXT NOT NULL,
    display_name TEXT,
    is_custom   INTEGER DEFAULT 0,
    created_at  TEXT DEFAULT (datetime('now')),
    UNIQUE(provider_id, model_name)
);

CREATE TABLE IF NOT EXISTS stats_hourly (
    hour                TEXT,
    provider            TEXT,
    model               TEXT,
    request_count       INTEGER DEFAULT 0,
    error_count         INTEGER DEFAULT 0,
    total_input_tokens  INTEGER DEFAULT 0,
    total_output_tokens INTEGER DEFAULT 0,
    avg_duration_ms     REAL DEFAULT 0,
    PRIMARY KEY (hour, provider, model)
);

CREATE TABLE IF NOT EXISTS settings (
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    updated_at TEXT DEFAULT (datetime('now'))
);
"#;
