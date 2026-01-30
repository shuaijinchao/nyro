/*
 * APIOAK Router Engine Implementation
 * 
 * 基于 rax (Radix Tree) 和 khash 的高性能路由引擎
 */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "apioak_router.h"
#include "rax.h"
#include "khash.h"

/* ============================================================
 * 内部数据结构
 * ============================================================ */

/* 路由条目 */
typedef struct {
    char *path;                 /* 原始路径模式 */
    size_t path_len;
    char *host;                 /* 主机名 */
    size_t host_len;
    uint32_t methods;           /* HTTP 方法位掩码 */
    int match_type;             /* 匹配类型 */
    int priority;               /* 优先级 */
    uintptr_t handler;          /* 处理器 ID */
    char *regex_pattern;        /* 正则模式 (仅 REGEX 类型) */
} route_entry_t;

/* 路由列表 (用于存储同一前缀下的多个路由) */
typedef struct {
    route_entry_t **entries;
    size_t count;
    size_t capacity;
} route_list_t;

/* Host 索引的 khash 定义 */
KHASH_MAP_INIT_STR(host_map, rax*)

/* 路由器主结构 */
struct apioak_router_s {
    rax *exact_tree;            /* 精确匹配树 */
    rax *prefix_tree;           /* 前缀匹配树 */
    rax *param_tree;            /* 参数匹配树 */
    route_list_t *regex_routes; /* 正则路由列表 */
    
    khash_t(host_map) *host_index;  /* Host -> Tree 索引 */
    
    route_entry_t **all_routes; /* 所有路由的引用 */
    size_t route_count;
    size_t route_capacity;
    
    int is_built;               /* 是否已构建索引 */
};

/* ============================================================
 * 辅助函数
 * ============================================================ */

static route_list_t *route_list_new(void) {
    route_list_t *list = malloc(sizeof(route_list_t));
    if (!list) return NULL;
    
    list->entries = NULL;
    list->count = 0;
    list->capacity = 0;
    return list;
}

static int route_list_add(route_list_t *list, route_entry_t *entry) {
    if (list->count >= list->capacity) {
        size_t new_cap = list->capacity == 0 ? 4 : list->capacity * 2;
        route_entry_t **new_entries = realloc(list->entries, 
                                               new_cap * sizeof(route_entry_t*));
        if (!new_entries) return APIOAK_ROUTER_ERR_NOMEM;
        list->entries = new_entries;
        list->capacity = new_cap;
    }
    list->entries[list->count++] = entry;
    return APIOAK_ROUTER_OK;
}

static void route_list_free(route_list_t *list) {
    if (list) {
        free(list->entries);
        free(list);
    }
}

static route_entry_t *route_entry_new(const char *host, 
                                       const char *path,
                                       size_t path_len,
                                       uint32_t methods,
                                       int match_type,
                                       int priority,
                                       uintptr_t handler) {
    route_entry_t *entry = malloc(sizeof(route_entry_t));
    if (!entry) return NULL;
    
    entry->path = malloc(path_len + 1);
    if (!entry->path) {
        free(entry);
        return NULL;
    }
    memcpy(entry->path, path, path_len);
    entry->path[path_len] = '\0';
    entry->path_len = path_len;
    
    if (host && *host) {
        entry->host_len = strlen(host);
        entry->host = malloc(entry->host_len + 1);
        if (!entry->host) {
            free(entry->path);
            free(entry);
            return NULL;
        }
        memcpy(entry->host, host, entry->host_len + 1);
    } else {
        entry->host = NULL;
        entry->host_len = 0;
    }
    
    entry->methods = methods;
    entry->match_type = match_type;
    entry->priority = priority;
    entry->handler = handler;
    entry->regex_pattern = NULL;
    
    return entry;
}

static void route_entry_free(route_entry_t *entry) {
    if (entry) {
        free(entry->path);
        free(entry->host);
        free(entry->regex_pattern);
        free(entry);
    }
}

/* 比较优先级 (用于排序) */
static int compare_priority(const void *a, const void *b) {
    const route_entry_t *ra = *(const route_entry_t**)a;
    const route_entry_t *rb = *(const route_entry_t**)b;
    return rb->priority - ra->priority;  /* 降序 */
}

/* 解析参数路径，提取固定前缀
 * 参数格式: {name}，例如 /user/{id}/profile/{name}
 */
static size_t extract_static_prefix(const char *path, size_t len) {
    for (size_t i = 0; i < len; i++) {
        if (path[i] == '{' || path[i] == '*') {
            /* 回退到上一个 '/' */
            while (i > 0 && path[i-1] != '/') i--;
            return i;
        }
    }
    return len;
}

/* 匹配参数路径
 * 参数格式: {name}，例如 /user/{id}/profile/{name}
 */
static int match_param_path(const char *pattern, size_t pattern_len,
                            const char *path, size_t path_len,
                            apioak_router_match_result_t *result) {
    size_t pi = 0, ri = 0;
    int param_count = 0;
    apioak_router_param_t params[16];  /* 最多 16 个参数 */
    
    while (pi < pattern_len && ri < path_len) {
        if (pattern[pi] == '{') {
            /* 参数匹配: {name} */
            pi++;  /* 跳过 '{' */
            
            /* 获取参数名 (直到 '}') */
            size_t name_start = pi;
            while (pi < pattern_len && pattern[pi] != '}') pi++;
            size_t name_len = pi - name_start;
            
            if (pi < pattern_len && pattern[pi] == '}') {
                pi++;  /* 跳过 '}' */
            }
            
            /* 获取参数值 (直到下一个 '/') */
            size_t value_start = ri;
            while (ri < path_len && path[ri] != '/') ri++;
            
            if (param_count < 16) {
                params[param_count].name = pattern + name_start;
                params[param_count].name_len = name_len;
                params[param_count].value = path + value_start;
                params[param_count].value_len = ri - value_start;
                param_count++;
            }
        } else if (pattern[pi] == '*') {
            /* 通配符，匹配剩余所有 */
            if (param_count < 16) {
                params[param_count].name = "*";
                params[param_count].name_len = 1;
                params[param_count].value = path + ri;
                params[param_count].value_len = path_len - ri;
                param_count++;
            }
            pi = pattern_len;
            ri = path_len;
            break;
        } else {
            /* 精确匹配字符 */
            if (pattern[pi] != path[ri]) return 0;
            pi++;
            ri++;
        }
    }
    
    /* 检查是否完全匹配 */
    if (pi != pattern_len || ri != path_len) return 0;
    
    /* 复制参数到结果 */
    if (param_count > 0 && result) {
        result->params = malloc(param_count * sizeof(apioak_router_param_t));
        if (result->params) {
            memcpy(result->params, params, param_count * sizeof(apioak_router_param_t));
            result->param_count = param_count;
        }
    }
    
    return 1;
}

/* ============================================================
 * 公共 API 实现
 * ============================================================ */

apioak_router_t *apioak_router_new(void) {
    apioak_router_t *router = malloc(sizeof(apioak_router_t));
    if (!router) return NULL;
    
    router->exact_tree = raxNew();
    router->prefix_tree = raxNew();
    router->param_tree = raxNew();
    router->regex_routes = route_list_new();
    router->host_index = kh_init(host_map);
    
    router->all_routes = NULL;
    router->route_count = 0;
    router->route_capacity = 0;
    router->is_built = 0;
    
    if (!router->exact_tree || !router->prefix_tree || 
        !router->param_tree || !router->regex_routes ||
        !router->host_index) {
        apioak_router_free(router);
        return NULL;
    }
    
    return router;
}

void apioak_router_free(apioak_router_t *router) {
    if (!router) return;
    
    /* 释放所有路由条目 */
    for (size_t i = 0; i < router->route_count; i++) {
        route_entry_free(router->all_routes[i]);
    }
    free(router->all_routes);
    
    /* 释放树 */
    if (router->exact_tree) raxFree(router->exact_tree);
    if (router->prefix_tree) raxFree(router->prefix_tree);
    if (router->param_tree) raxFree(router->param_tree);
    
    /* 释放正则列表 */
    route_list_free(router->regex_routes);
    
    /* 释放 host 索引 */
    if (router->host_index) {
        kh_destroy(host_map, router->host_index);
    }
    
    free(router);
}

int apioak_router_add(apioak_router_t *router,
                      const char *host,
                      const char *path,
                      size_t path_len,
                      uint32_t methods,
                      int match_type,
                      int priority,
                      uintptr_t handler) {
    if (!router || !path || path_len == 0) {
        return APIOAK_ROUTER_ERR_INVALID;
    }
    
    /* 创建路由条目 */
    route_entry_t *entry = route_entry_new(host, path, path_len, 
                                            methods, match_type, 
                                            priority, handler);
    if (!entry) return APIOAK_ROUTER_ERR_NOMEM;
    
    /* 添加到全局列表 */
    if (router->route_count >= router->route_capacity) {
        size_t new_cap = router->route_capacity == 0 ? 16 : router->route_capacity * 2;
        route_entry_t **new_routes = realloc(router->all_routes, 
                                              new_cap * sizeof(route_entry_t*));
        if (!new_routes) {
            route_entry_free(entry);
            return APIOAK_ROUTER_ERR_NOMEM;
        }
        router->all_routes = new_routes;
        router->route_capacity = new_cap;
    }
    router->all_routes[router->route_count++] = entry;
    
    router->is_built = 0;  /* 需要重新构建 */
    return APIOAK_ROUTER_OK;
}

int apioak_router_build(apioak_router_t *router) {
    if (!router) return APIOAK_ROUTER_ERR_INVALID;
    
    /* 按优先级排序 */
    if (router->route_count > 1) {
        qsort(router->all_routes, router->route_count, 
              sizeof(route_entry_t*), compare_priority);
    }
    
    /* 清空现有树 */
    raxFree(router->exact_tree);
    raxFree(router->prefix_tree);
    raxFree(router->param_tree);
    router->exact_tree = raxNew();
    router->prefix_tree = raxNew();
    router->param_tree = raxNew();
    router->regex_routes->count = 0;
    
    /* 构建索引 */
    for (size_t i = 0; i < router->route_count; i++) {
        route_entry_t *entry = router->all_routes[i];
        rax *tree = NULL;
        
        switch (entry->match_type) {
            case APIOAK_ROUTER_MATCH_EXACT:
                tree = router->exact_tree;
                raxInsert(tree, (unsigned char*)entry->path, 
                         entry->path_len, entry, NULL);
                break;
                
            case APIOAK_ROUTER_MATCH_PREFIX:
                tree = router->prefix_tree;
                /* 移除尾部的通配符 */
                {
                    size_t len = entry->path_len;
                    if (len > 0 && entry->path[len-1] == '*') len--;
                    if (len > 0 && entry->path[len-1] == '/') len--;
                    raxInsert(tree, (unsigned char*)entry->path, len, entry, NULL);
                }
                break;
                
            case APIOAK_ROUTER_MATCH_PARAM:
                tree = router->param_tree;
                /* 使用静态前缀作为索引 */
                {
                    size_t prefix_len = extract_static_prefix(entry->path, entry->path_len);
                    if (prefix_len > 0) {
                        /* 在前缀节点下存储路由列表 */
                        void *old = NULL;
                        route_list_t *list = raxFind(tree, (unsigned char*)entry->path, prefix_len);
                        if (list == raxNotFound) {
                            list = route_list_new();
                            raxInsert(tree, (unsigned char*)entry->path, prefix_len, list, &old);
                        }
                        route_list_add(list, entry);
                    }
                }
                break;
                
            case APIOAK_ROUTER_MATCH_REGEX:
                route_list_add(router->regex_routes, entry);
                break;
        }
    }
    
    router->is_built = 1;
    return APIOAK_ROUTER_OK;
}

int apioak_router_match(apioak_router_t *router,
                        const char *host,
                        size_t host_len,
                        const char *path,
                        size_t path_len,
                        uint32_t method,
                        apioak_router_match_result_t *result) {
    if (!router || !path || !result) return 0;
    
    (void)host;      /* TODO: host 匹配 */
    (void)host_len;
    
    memset(result, 0, sizeof(*result));
    
    /* 1. 精确匹配 (优先级最高) */
    route_entry_t *entry = raxFind(router->exact_tree, 
                                    (unsigned char*)path, path_len);
    if (entry != raxNotFound) {
        if (entry->methods & method) {
            result->handler = entry->handler;
            result->match_type = APIOAK_ROUTER_MATCH_EXACT;
            return 1;
        }
    }
    
    /* 2. 前缀匹配 (最长前缀优先) */
    raxIterator iter;
    raxStart(&iter, router->prefix_tree);
    raxSeek(&iter, "<=", (unsigned char*)path, path_len);
    
    while (raxPrev(&iter)) {
        /* 检查是否是前缀 */
        if (iter.key_len <= path_len && 
            memcmp(iter.key, path, iter.key_len) == 0) {
            /* 确保在路径边界 */
            if (iter.key_len == path_len || path[iter.key_len] == '/') {
                entry = iter.data;
                if (entry->methods & method) {
                    result->handler = entry->handler;
                    result->match_type = APIOAK_ROUTER_MATCH_PREFIX;
                    raxStop(&iter);
                    return 1;
                }
            }
        }
        break;  /* 只检查最长前缀 */
    }
    raxStop(&iter);
    
    /* 3. 参数匹配 */
    raxStart(&iter, router->param_tree);
    raxSeek(&iter, "<=", (unsigned char*)path, path_len);
    
    while (raxPrev(&iter)) {
        if (iter.key_len <= path_len && 
            memcmp(iter.key, path, iter.key_len) == 0) {
            route_list_t *list = iter.data;
            for (size_t i = 0; i < list->count; i++) {
                entry = list->entries[i];
                if (entry->methods & method) {
                    if (match_param_path(entry->path, entry->path_len,
                                        path, path_len, result)) {
                        result->handler = entry->handler;
                        result->match_type = APIOAK_ROUTER_MATCH_PARAM;
                        raxStop(&iter);
                        return 1;
                    }
                }
            }
        }
        break;
    }
    raxStop(&iter);
    
    /* 4. 正则匹配 (TODO: 需要 PCRE 支持，暂时跳过) */
    /* 正则匹配建议在 Lua 层使用 ngx.re.match 实现 */
    
    return 0;
}

void apioak_router_match_result_free(apioak_router_match_result_t *result) {
    if (result && result->params) {
        free(result->params);
        result->params = NULL;
        result->param_count = 0;
    }
}

size_t apioak_router_count(apioak_router_t *router) {
    return router ? router->route_count : 0;
}

void apioak_router_clear(apioak_router_t *router) {
    if (!router) return;
    
    for (size_t i = 0; i < router->route_count; i++) {
        route_entry_free(router->all_routes[i]);
    }
    router->route_count = 0;
    router->is_built = 0;
}
