mod matcher;

pub use matcher::RouteCache;

use crate::db::models::Route;

impl RouteCache {
    pub fn match_route(&self, model: &str) -> Option<&Route> {
        matcher::match_route(&self.routes, model)
    }
}
