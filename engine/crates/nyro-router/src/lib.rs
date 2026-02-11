//! NYRO Router Engine
//!
//! High-performance URL router based on matchit (radix tree).
//! Supports exact match, prefix match, and parameter match.
//! Regex match is delegated to the Lua layer (ngx.re).

use std::collections::HashMap;

// ============================================================
// Constants
// ============================================================

/// Match type: exact path
pub const MATCH_EXACT: i32 = 1;
/// Match type: prefix (longest prefix wins)
pub const MATCH_PREFIX: i32 = 2;
/// Match type: parameter (e.g. `/users/{id}`)
pub const MATCH_PARAM: i32 = 3;

/// Success
pub const OK: i32 = 0;
/// Generic error
pub const ERR: i32 = -1;
/// Invalid argument
pub const ERR_INVALID: i32 = -3;

// ============================================================
// Public types
// ============================================================

/// A matched parameter (name-value pair).
pub struct MatchParam {
    pub name: String,
    pub value: String,
}

/// Result of a successful route match.
pub struct MatchResult {
    pub handler: usize,
    pub params: Vec<MatchParam>,
    pub match_type: i32,
}

// ============================================================
// Internal types
// ============================================================

/// A single route entry with metadata.
#[derive(Clone)]
struct RouteEntry {
    host: Option<String>,
    methods: u32,
    priority: i32,
    handler: usize,
    match_type: i32,
}

/// Pending route before build().
struct Pending {
    path: String,
    entry: RouteEntry,
}

// ============================================================
// Helpers
// ============================================================

/// Escape `{` and `}` so matchit treats them as literals.
fn escape_braces(path: &str) -> String {
    path.replace('{', "{{").replace('}', "}}")
}

/// Check if a route entry matches the request host and method.
fn entry_matches(entry: &RouteEntry, host: Option<&str>, method: u32) -> bool {
    // Method check (0xFFFFFFFF = match all)
    if entry.methods != 0xFFFFFFFF && (entry.methods & method) == 0 {
        return false;
    }
    // Host check (None = match all)
    if let Some(ref entry_host) = entry.host {
        match host {
            Some(h) if h == entry_host.as_str() => {}
            _ => return false,
        }
    }
    true
}

// ============================================================
// Router
// ============================================================

/// High-performance URL router.
pub struct Router {
    /// matchit router for exact + param + prefix matching.
    tree: Option<matchit::Router<Vec<RouteEntry>>>,
    /// Pending routes accumulated before build().
    pending: Vec<Pending>,
    /// Total route count.
    route_count: usize,
    /// Whether build() has been called.
    is_built: bool,
}

impl Router {
    /// Create a new empty router.
    pub fn new() -> Self {
        Router {
            tree: None,
            pending: Vec::new(),
            route_count: 0,
            is_built: false,
        }
    }

    /// Add a route.
    ///
    /// - `host`: optional host filter (`None` or `"*"` = match all).
    /// - `path`: URL path pattern.
    /// - `methods`: HTTP method bitmask (0xFFFFFFFF = all).
    /// - `match_type`: one of `MATCH_EXACT`, `MATCH_PREFIX`, `MATCH_PARAM`.
    /// - `priority`: higher value = higher priority within the same match type.
    /// - `handler`: opaque handler ID passed back on match.
    pub fn add(
        &mut self,
        host: Option<&str>,
        path: &str,
        methods: u32,
        match_type: i32,
        priority: i32,
        handler: usize,
    ) -> i32 {
        if path.is_empty() {
            return ERR_INVALID;
        }

        let entry = RouteEntry {
            host: host.and_then(|h| {
                if h.is_empty() || h == "*" {
                    None
                } else {
                    Some(h.to_string())
                }
            }),
            methods,
            priority,
            handler,
            match_type,
        };

        match match_type {
            MATCH_EXACT => {
                // Escape braces so matchit treats {/} as literal characters.
                self.pending.push(Pending {
                    path: escape_braces(path),
                    entry,
                });
            }
            MATCH_PARAM => {
                // matchit natively understands `{param}` syntax.
                self.pending.push(Pending {
                    path: path.to_string(),
                    entry,
                });
            }
            MATCH_PREFIX => {
                // Convert PREFIX to matchit catch-all syntax.
                // Strip trailing `*` if present, keep the prefix.
                let clean = path.strip_suffix('*').unwrap_or(path);
                let clean = if clean.is_empty() { "/" } else { clean };
                let escaped = escape_braces(clean);

                // 1. Exact prefix path (e.g. "/api" or "/api/")
                self.pending.push(Pending {
                    path: escaped.clone(),
                    entry: entry.clone(),
                });

                // 2. Catch-all sub-paths with segment boundary enforcement.
                // For "/api" -> "/api/{*_prefix}" (matches /api/foo but NOT /api-v2)
                // For "/api/" -> "/api/{*_prefix}" (same pattern)
                let base = escaped.trim_end_matches('/');
                let catchall = format!("{}/{{*_prefix}}", base);
                self.pending.push(Pending {
                    path: catchall,
                    entry,
                });
            }
            _ => return ERR_INVALID,
        }

        self.route_count += 1;
        self.is_built = false;
        OK
    }

    /// Build the router index. Must be called after adding all routes
    /// and before calling `match_route`.
    pub fn build(&mut self) -> i32 {
        if self.is_built {
            return OK;
        }

        // ---- group pending routes by path ----
        let mut tree_groups: HashMap<String, Vec<RouteEntry>> = HashMap::new();

        for pending in self.pending.drain(..) {
            tree_groups.entry(pending.path).or_default().push(pending.entry);
        }

        // ---- build matchit router (exact + param + prefix) ----
        let mut router = matchit::Router::new();

        for (path, mut entries) in tree_groups {
            // Sort by priority descending, then by match_type ascending
            // (EXACT=1 wins over PREFIX=2).
            entries.sort_by(|a, b| {
                b.priority
                    .cmp(&a.priority)
                    .then(a.match_type.cmp(&b.match_type))
            });
            // On conflict (e.g. /{id} vs /{name}), skip silently.
            let _ = router.insert(path, entries);
        }

        self.tree = Some(router);
        self.is_built = true;
        OK
    }

    /// Match a route against the given request parameters.
    ///
    /// Returns `Some(MatchResult)` on success, `None` if no route matches.
    /// Match priority: **exact > param > prefix** (handled by matchit radix tree).
    pub fn match_route(
        &self,
        host: Option<&str>,
        path: &str,
        method: u32,
    ) -> Option<MatchResult> {
        if !self.is_built {
            return None;
        }

        // Try matchit (exact + param + prefix via catch-all).
        if let Some(ref tree) = self.tree {
            if let Ok(matched) = tree.at(path) {
                for entry in matched.value.iter() {
                    if entry_matches(entry, host, method) {
                        // Filter out the synthetic `_prefix` param from catch-all routes.
                        let params: Vec<MatchParam> = matched
                            .params
                            .iter()
                            .filter(|(k, _)| *k != "_prefix")
                            .map(|(k, v)| MatchParam {
                                name: k.to_string(),
                                value: v.to_string(),
                            })
                            .collect();

                        return Some(MatchResult {
                            handler: entry.handler,
                            params,
                            match_type: entry.match_type,
                        });
                    }
                }
            }
        }

        None
    }

    /// Return the total number of routes added.
    pub fn count(&self) -> usize {
        self.route_count
    }

    /// Remove all routes and reset the router.
    pub fn clear(&mut self) {
        self.tree = None;
        self.pending.clear();
        self.route_count = 0;
        self.is_built = false;
    }
}

impl Default for Router {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================
// Tests
// ============================================================

#[cfg(test)]
mod tests {
    use super::*;

    const METHOD_ALL: u32 = 0xFFFFFFFF;
    const METHOD_GET: u32 = 0x001;
    const METHOD_POST: u32 = 0x002;

    #[test]
    fn test_exact_match() {
        let mut r = Router::new();
        assert_eq!(r.add(None, "/api/users", METHOD_ALL, MATCH_EXACT, 0, 1), OK);
        assert_eq!(r.build(), OK);

        let m = r.match_route(None, "/api/users", METHOD_GET).unwrap();
        assert_eq!(m.handler, 1);
        assert_eq!(m.match_type, MATCH_EXACT);
        assert!(m.params.is_empty());

        // Should not match different path.
        assert!(r.match_route(None, "/api/orders", METHOD_GET).is_none());
    }

    #[test]
    fn test_param_match() {
        let mut r = Router::new();
        assert_eq!(
            r.add(None, "/api/users/{id}", METHOD_ALL, MATCH_PARAM, 0, 1),
            OK
        );
        assert_eq!(r.build(), OK);

        let m = r.match_route(None, "/api/users/123", METHOD_GET).unwrap();
        assert_eq!(m.handler, 1);
        assert_eq!(m.match_type, MATCH_PARAM);
        assert_eq!(m.params.len(), 1);
        assert_eq!(m.params[0].name, "id");
        assert_eq!(m.params[0].value, "123");
    }

    #[test]
    fn test_multi_param() {
        let mut r = Router::new();
        assert_eq!(
            r.add(
                None,
                "/api/{version}/users/{id}",
                METHOD_ALL,
                MATCH_PARAM,
                0,
                1
            ),
            OK
        );
        assert_eq!(r.build(), OK);

        let m = r.match_route(None, "/api/v2/users/42", METHOD_GET).unwrap();
        assert_eq!(m.handler, 1);
        assert_eq!(m.params.len(), 2);

        let names: Vec<&str> = m.params.iter().map(|p| p.name.as_str()).collect();
        assert!(names.contains(&"version"));
        assert!(names.contains(&"id"));
    }

    #[test]
    fn test_prefix_match() {
        let mut r = Router::new();
        assert_eq!(
            r.add(None, "/api/v1/*", METHOD_ALL, MATCH_PREFIX, 0, 1),
            OK
        );
        assert_eq!(r.build(), OK);

        // Exact prefix path.
        let m = r.match_route(None, "/api/v1/", METHOD_GET).unwrap();
        assert_eq!(m.handler, 1);
        assert_eq!(m.match_type, MATCH_PREFIX);

        // Extended path.
        let m = r.match_route(None, "/api/v1/users/123", METHOD_GET).unwrap();
        assert_eq!(m.handler, 1);

        // Should not match different prefix.
        assert!(r.match_route(None, "/api/v2/users", METHOD_GET).is_none());
    }

    #[test]
    fn test_prefix_boundary() {
        let mut r = Router::new();
        assert_eq!(r.add(None, "/api", METHOD_ALL, MATCH_PREFIX, 0, 1), OK);
        assert_eq!(r.build(), OK);

        // Exact.
        assert!(r.match_route(None, "/api", METHOD_GET).is_some());
        // With slash.
        assert!(r.match_route(None, "/api/foo", METHOD_GET).is_some());
        // NOT a boundary match.
        assert!(r.match_route(None, "/api-v2", METHOD_GET).is_none());
    }

    #[test]
    fn test_exact_over_param() {
        let mut r = Router::new();
        assert_eq!(
            r.add(None, "/api/users", METHOD_ALL, MATCH_EXACT, 0, 1),
            OK
        );
        assert_eq!(
            r.add(None, "/api/{resource}", METHOD_ALL, MATCH_PARAM, 0, 2),
            OK
        );
        assert_eq!(r.build(), OK);

        // Static wins.
        let m = r.match_route(None, "/api/users", METHOD_GET).unwrap();
        assert_eq!(m.handler, 1);
        assert_eq!(m.match_type, MATCH_EXACT);

        // Param fallback.
        let m = r.match_route(None, "/api/orders", METHOD_GET).unwrap();
        assert_eq!(m.handler, 2);
        assert_eq!(m.match_type, MATCH_PARAM);
    }

    #[test]
    fn test_method_filter() {
        let mut r = Router::new();
        assert_eq!(
            r.add(None, "/api/users", METHOD_GET, MATCH_EXACT, 0, 1),
            OK
        );
        assert_eq!(r.build(), OK);

        // GET matches.
        assert!(r.match_route(None, "/api/users", METHOD_GET).is_some());
        // POST does not.
        assert!(r.match_route(None, "/api/users", METHOD_POST).is_none());
    }

    #[test]
    fn test_same_path_different_methods() {
        let mut r = Router::new();
        assert_eq!(
            r.add(None, "/api/users", METHOD_GET, MATCH_EXACT, 0, 1),
            OK
        );
        assert_eq!(
            r.add(None, "/api/users", METHOD_POST, MATCH_EXACT, 0, 2),
            OK
        );
        assert_eq!(r.build(), OK);

        let m = r.match_route(None, "/api/users", METHOD_GET).unwrap();
        assert_eq!(m.handler, 1);

        let m = r.match_route(None, "/api/users", METHOD_POST).unwrap();
        assert_eq!(m.handler, 2);
    }

    #[test]
    fn test_host_filter() {
        let mut r = Router::new();
        assert_eq!(
            r.add(
                Some("api.example.com"),
                "/api",
                METHOD_ALL,
                MATCH_EXACT,
                0,
                1
            ),
            OK
        );
        assert_eq!(
            r.add(None, "/api", METHOD_ALL, MATCH_EXACT, 0, 2),
            OK
        );
        assert_eq!(r.build(), OK);

        // With matching host → handler 1 (higher priority by insertion order, both prio=0).
        let m = r
            .match_route(Some("api.example.com"), "/api", METHOD_GET)
            .unwrap();
        assert_eq!(m.handler, 1);

        // With non-matching host → handler 2 (wildcard).
        let m = r
            .match_route(Some("other.com"), "/api", METHOD_GET)
            .unwrap();
        assert_eq!(m.handler, 2);
    }

    #[test]
    fn test_clear() {
        let mut r = Router::new();
        assert_eq!(r.add(None, "/api", METHOD_ALL, MATCH_EXACT, 0, 1), OK);
        assert_eq!(r.build(), OK);
        assert_eq!(r.count(), 1);

        r.clear();
        assert_eq!(r.count(), 0);
        assert!(r.match_route(None, "/api", METHOD_GET).is_none());
    }
}
