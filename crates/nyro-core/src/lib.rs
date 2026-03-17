pub mod admin;
pub mod config;
pub mod crypto;
pub mod db;
pub mod logging;
pub mod protocol;
pub mod proxy;
pub mod router;

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use sqlx::SqlitePool;
use tokio::sync::mpsc;

use config::GatewayConfig;
use logging::LogEntry;

#[derive(Clone, Debug)]
pub struct CapabilityCacheEntry {
    pub capabilities: Vec<String>,
    pub cached_at: Instant,
}

#[derive(Clone)]
pub struct Gateway {
    pub config: GatewayConfig,
    pub db: SqlitePool,
    pub http_client: reqwest::Client,
    pub route_cache: Arc<tokio::sync::RwLock<router::RouteCache>>,
    pub ollama_capability_cache: Arc<tokio::sync::RwLock<HashMap<String, CapabilityCacheEntry>>>,
    pub log_tx: mpsc::Sender<LogEntry>,
}

impl Gateway {
    pub async fn new(config: GatewayConfig) -> anyhow::Result<(Self, mpsc::Receiver<LogEntry>)> {
        let db = db::init_pool(&config.data_dir).await?;
        db::migrate(&db).await?;

        let http_client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(300))
            .build()?;

        let route_cache = Arc::new(tokio::sync::RwLock::new(
            router::RouteCache::load(&db).await?,
        ));
        let ollama_capability_cache = Arc::new(tokio::sync::RwLock::new(HashMap::new()));

        let (log_tx, log_rx) = mpsc::channel(1024);

        let gw = Self {
            config,
            db,
            http_client,
            route_cache,
            ollama_capability_cache,
            log_tx,
        };

        Ok((gw, log_rx))
    }

    pub async fn start_proxy(&self) -> anyhow::Result<()> {
        let router = proxy::server::create_router(self.clone());
        let addr = format!("{}:{}", self.config.proxy_host, self.config.proxy_port);
        let listener = tokio::net::TcpListener::bind(&addr).await?;
        tracing::info!("proxy listening on {}", addr);
        axum::serve(listener, router).await?;
        Ok(())
    }

    pub fn admin(&self) -> admin::AdminService {
        admin::AdminService::new(self.clone())
    }

    pub async fn get_ollama_capabilities_cached(
        &self,
        provider_id: &str,
        model: &str,
        ttl: Duration,
    ) -> Option<Vec<String>> {
        let key = format!("{provider_id}:{model}");
        let cache = self.ollama_capability_cache.read().await;
        cache.get(&key).and_then(|entry| {
            if entry.cached_at.elapsed() < ttl {
                Some(entry.capabilities.clone())
            } else {
                None
            }
        })
    }

    pub async fn set_ollama_capabilities_cache(
        &self,
        provider_id: &str,
        model: &str,
        capabilities: Vec<String>,
    ) {
        let key = format!("{provider_id}:{model}");
        let mut cache = self.ollama_capability_cache.write().await;
        cache.insert(
            key,
            CapabilityCacheEntry {
                capabilities,
                cached_at: Instant::now(),
            },
        );
    }

    pub async fn clear_ollama_capability_cache_for_provider(&self, provider_id: &str) {
        let prefix = format!("{provider_id}:");
        let mut cache = self.ollama_capability_cache.write().await;
        cache.retain(|k, _| !k.starts_with(&prefix));
    }
}
