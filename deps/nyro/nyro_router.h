/*
 * NYRO Router Engine
 * 
 * 基于 rax (Radix Tree) 和 khash 的高性能路由引擎
 * 支持：精确匹配、前缀匹配、参数匹配、正则匹配
 */

#ifndef NYRO_ROUTER_H
#define NYRO_ROUTER_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 匹配类型 */
#define NYRO_ROUTER_MATCH_EXACT   1   /* 精确匹配: /api/v1/users */
#define NYRO_ROUTER_MATCH_PREFIX  2   /* 前缀匹配: /api/v1/wildcard */
#define NYRO_ROUTER_MATCH_PARAM   3   /* 参数匹配: /user/{id}/profile */
#define NYRO_ROUTER_MATCH_REGEX   4   /* 正则匹配: ^/api/v[0-9]+/.* */

/* 错误码 */
#define NYRO_ROUTER_OK            0
#define NYRO_ROUTER_ERR           -1
#define NYRO_ROUTER_ERR_NOMEM     -2
#define NYRO_ROUTER_ERR_INVALID   -3

/* 路由器句柄 */
typedef struct nyro_router_s nyro_router_t;

/* 路由参数 (用于参数匹配) */
typedef struct {
    const char *name;       /* 参数名 (不含 :) */
    const char *value;      /* 参数值 */
    size_t name_len;
    size_t value_len;
} nyro_router_param_t;

/* 匹配结果 */
typedef struct {
    uintptr_t handler;                  /* 路由处理器 ID */
    nyro_router_param_t *params;      /* 参数数组 */
    int param_count;                    /* 参数数量 */
    int match_type;                     /* 匹配类型 */
} nyro_router_match_result_t;

/*
 * 创建路由器实例
 * 
 * @return 路由器句柄，失败返回 NULL
 */
nyro_router_t *nyro_router_new(void);

/*
 * 销毁路由器实例
 * 
 * @param router 路由器句柄
 */
void nyro_router_free(nyro_router_t *router);

/*
 * 添加路由规则
 * 
 * @param router     路由器句柄
 * @param host       主机名 (可为 NULL 表示匹配所有)
 * @param path       路径模式
 * @param path_len   路径长度
 * @param methods    HTTP 方法位掩码 (GET=1, POST=2, PUT=4, DELETE=8, ...)
 * @param match_type 匹配类型 (NYRO_ROUTER_MATCH_*)
 * @param priority   优先级 (数字越大优先级越高)
 * @param handler    处理器 ID
 * 
 * @return NYRO_ROUTER_OK 成功，其他表示失败
 */
int nyro_router_add(nyro_router_t *router,
                      const char *host,
                      const char *path,
                      size_t path_len,
                      uint32_t methods,
                      int match_type,
                      int priority,
                      uintptr_t handler);

/*
 * 构建路由索引 (添加完所有路由后调用)
 * 
 * @param router 路由器句柄
 * 
 * @return NYRO_ROUTER_OK 成功
 */
int nyro_router_build(nyro_router_t *router);

/*
 * 匹配路由
 * 
 * @param router     路由器句柄
 * @param host       请求主机名
 * @param host_len   主机名长度
 * @param path       请求路径
 * @param path_len   路径长度
 * @param method     HTTP 方法位掩码
 * @param result     匹配结果 (输出参数)
 * 
 * @return 1 匹配成功，0 无匹配
 */
int nyro_router_match(nyro_router_t *router,
                        const char *host,
                        size_t host_len,
                        const char *path,
                        size_t path_len,
                        uint32_t method,
                        nyro_router_match_result_t *result);

/*
 * 释放匹配结果中的参数内存
 * 
 * @param result 匹配结果
 */
void nyro_router_match_result_free(nyro_router_match_result_t *result);

/*
 * 获取路由数量
 * 
 * @param router 路由器句柄
 * 
 * @return 路由数量
 */
size_t nyro_router_count(nyro_router_t *router);

/*
 * 清空所有路由
 * 
 * @param router 路由器句柄
 */
void nyro_router_clear(nyro_router_t *router);

/* HTTP 方法位掩码定义 */
#define NYRO_ROUTER_METHOD_GET     (1 << 0)
#define NYRO_ROUTER_METHOD_POST    (1 << 1)
#define NYRO_ROUTER_METHOD_PUT     (1 << 2)
#define NYRO_ROUTER_METHOD_DELETE  (1 << 3)
#define NYRO_ROUTER_METHOD_PATCH   (1 << 4)
#define NYRO_ROUTER_METHOD_HEAD    (1 << 5)
#define NYRO_ROUTER_METHOD_OPTIONS (1 << 6)
#define NYRO_ROUTER_METHOD_CONNECT (1 << 7)
#define NYRO_ROUTER_METHOD_TRACE   (1 << 8)
#define NYRO_ROUTER_METHOD_ALL     0xFFFFFFFF

#ifdef __cplusplus
}
#endif

#endif /* NYRO_ROUTER_H */
