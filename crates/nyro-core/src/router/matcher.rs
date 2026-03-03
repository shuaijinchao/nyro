use sqlx::SqlitePool;

use crate::db::models::Route;

pub struct RouteCache {
    pub routes: Vec<Route>,
}

impl RouteCache {
    pub async fn load(pool: &SqlitePool) -> anyhow::Result<Self> {
        let routes: Vec<Route> = sqlx::query_as::<_, Route>(
            r#"SELECT
                id, name, match_pattern, target_provider, target_model,
                fallback_provider, fallback_model,
                is_active,
                priority,
                created_at
            FROM routes
            WHERE is_active = 1
            ORDER BY priority ASC"#,
        )
        .fetch_all(pool)
        .await?;

        Ok(Self { routes })
    }

    pub async fn reload(&mut self, pool: &SqlitePool) -> anyhow::Result<()> {
        *self = Self::load(pool).await?;
        Ok(())
    }
}

pub fn match_route<'a>(routes: &'a [Route], model: &str) -> Option<&'a Route> {
    routes
        .iter()
        .find(|r| pattern_matches(&r.match_pattern, model))
}

fn pattern_matches(pattern: &str, model: &str) -> bool {
    if pattern == "*" {
        return true;
    }
    glob_match::glob_match(pattern, model)
}
