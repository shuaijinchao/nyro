use sqlx::Row;

use crate::db::models::*;
use crate::Gateway;

#[derive(Clone)]
pub struct AdminService {
    gw: Gateway,
}

impl AdminService {
    pub fn new(gw: Gateway) -> Self {
        Self { gw }
    }

    pub async fn list_providers(&self) -> anyhow::Result<Vec<Provider>> {
        let rows = sqlx::query_as::<_, Provider>(
            "SELECT id, name, protocol, base_url, api_key, is_active, priority, created_at, updated_at FROM providers ORDER BY priority ASC",
        )
        .fetch_all(&self.gw.db)
        .await?;
        Ok(rows)
    }

    pub async fn create_provider(&self, input: CreateProvider) -> anyhow::Result<Provider> {
        let id = uuid::Uuid::new_v4().to_string();
        sqlx::query(
            "INSERT INTO providers (id, name, protocol, base_url, api_key) VALUES (?, ?, ?, ?, ?)",
        )
        .bind(&id)
        .bind(&input.name)
        .bind(&input.protocol)
        .bind(&input.base_url)
        .bind(&input.api_key)
        .execute(&self.gw.db)
        .await?;

        let provider = sqlx::query_as::<_, Provider>(
            "SELECT id, name, protocol, base_url, api_key, is_active, priority, created_at, updated_at FROM providers WHERE id = ?",
        )
        .bind(&id)
        .fetch_one(&self.gw.db)
        .await?;
        Ok(provider)
    }

    pub async fn delete_provider(&self, id: &str) -> anyhow::Result<()> {
        sqlx::query("DELETE FROM providers WHERE id = ?")
            .bind(id)
            .execute(&self.gw.db)
            .await?;
        Ok(())
    }

    pub async fn list_routes(&self) -> anyhow::Result<Vec<Route>> {
        let rows = sqlx::query_as::<_, Route>(
            "SELECT id, name, match_pattern, target_provider, target_model, fallback_provider, fallback_model, is_active, priority, created_at FROM routes ORDER BY priority ASC",
        )
        .fetch_all(&self.gw.db)
        .await?;
        Ok(rows)
    }

    pub async fn create_route(&self, input: CreateRoute) -> anyhow::Result<Route> {
        let id = uuid::Uuid::new_v4().to_string();
        let max_priority: Option<i32> =
            sqlx::query("SELECT MAX(priority) as mp FROM routes")
                .fetch_one(&self.gw.db)
                .await?
                .try_get("mp")
                .ok();
        let priority = max_priority.unwrap_or(0) + 1;

        sqlx::query(
            "INSERT INTO routes (id, name, match_pattern, target_provider, target_model, fallback_provider, fallback_model, priority) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&id)
        .bind(&input.name)
        .bind(&input.match_pattern)
        .bind(&input.target_provider)
        .bind(&input.target_model)
        .bind(&input.fallback_provider)
        .bind(&input.fallback_model)
        .bind(priority)
        .execute(&self.gw.db)
        .await?;

        let route = sqlx::query_as::<_, Route>(
            "SELECT id, name, match_pattern, target_provider, target_model, fallback_provider, fallback_model, is_active, priority, created_at FROM routes WHERE id = ?",
        )
        .bind(&id)
        .fetch_one(&self.gw.db)
        .await?;

        self.gw
            .route_cache
            .write()
            .await
            .reload(&self.gw.db)
            .await?;

        Ok(route)
    }

    pub async fn delete_route(&self, id: &str) -> anyhow::Result<()> {
        sqlx::query("DELETE FROM routes WHERE id = ?")
            .bind(id)
            .execute(&self.gw.db)
            .await?;

        self.gw
            .route_cache
            .write()
            .await
            .reload(&self.gw.db)
            .await?;

        Ok(())
    }
}
