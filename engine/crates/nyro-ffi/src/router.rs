//! FFI bindings for the NYRO router engine.
//!
//! Exposes a C-compatible API identical to the former `libnyro_router`
//! so that the Lua FFI layer (`nyro/route/ffi.lua`) works without changes.

use std::ffi::CStr;
use std::os::raw::c_int;
use std::{ptr, slice};

use nyro_router::Router;

// ============================================================
// FFI-safe types (must match the Lua `ffi.cdef` declarations)
// ============================================================

/// Route parameter (name-value pair).
#[repr(C)]
pub struct NyroRouterParam {
    pub name: *const u8,
    pub value: *const u8,
    pub name_len: usize,
    pub value_len: usize,
}

/// Match result written by `nyro_router_match`.
#[repr(C)]
pub struct NyroRouterMatchResult {
    pub handler: usize,
    pub params: *mut NyroRouterParam,
    pub param_count: c_int,
    pub match_type: c_int,
}

// ============================================================
// Internal helpers
// ============================================================

/// Allocate a byte buffer on the heap and return a thin pointer.
/// The caller must later free it with `dealloc_bytes`.
fn alloc_bytes(data: &[u8]) -> *const u8 {
    if data.is_empty() {
        return ptr::null();
    }
    let mut boxed = data.to_vec().into_boxed_slice();
    let p = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    p
}

/// Free a buffer previously returned by `alloc_bytes`.
unsafe fn dealloc_bytes(p: *mut u8, len: usize) {
    if p.is_null() || len == 0 {
        return;
    }
    let raw = ptr::slice_from_raw_parts_mut(p, len);
    let _ = Box::from_raw(raw);
}

// ============================================================
// Public FFI API
// ============================================================

/// Create a new router instance.
#[no_mangle]
pub extern "C" fn nyro_router_new() -> *mut Router {
    Box::into_raw(Box::new(Router::new()))
}

/// Destroy a router instance.
#[no_mangle]
pub unsafe extern "C" fn nyro_router_free(router: *mut Router) {
    if !router.is_null() {
        let _ = Box::from_raw(router);
    }
}

/// Add a route.
///
/// Returns `0` on success, negative on error.
#[no_mangle]
pub unsafe extern "C" fn nyro_router_add(
    router: *mut Router,
    host: *const i8,
    path: *const i8,
    path_len: usize,
    methods: u32,
    match_type: c_int,
    priority: c_int,
    handler: usize,
) -> c_int {
    if router.is_null() || path.is_null() || path_len == 0 {
        return nyro_router::ERR_INVALID;
    }

    let router = &mut *router;

    // path is *not* null-terminated — use the explicit length.
    let path_bytes = slice::from_raw_parts(path as *const u8, path_len);
    let path_str = match std::str::from_utf8(path_bytes) {
        Ok(s) => s,
        Err(_) => return nyro_router::ERR_INVALID,
    };

    // host IS null-terminated (C string from Lua).
    let host_str = if host.is_null() {
        None
    } else {
        CStr::from_ptr(host).to_str().ok()
    };

    router.add(host_str, path_str, methods, match_type, priority, handler)
}

/// Build the router index. Must be called after adding all routes.
#[no_mangle]
pub unsafe extern "C" fn nyro_router_build(router: *mut Router) -> c_int {
    if router.is_null() {
        return nyro_router::ERR_INVALID;
    }
    (*router).build()
}

/// Match a request against the router.
///
/// Writes the result into `*result`.
/// Returns `1` on match, `0` on no-match.
#[no_mangle]
pub unsafe extern "C" fn nyro_router_match(
    router: *mut Router,
    host: *const i8,
    host_len: usize,
    path: *const i8,
    path_len: usize,
    method: u32,
    result: *mut NyroRouterMatchResult,
) -> c_int {
    if router.is_null() || path.is_null() || result.is_null() {
        return 0;
    }

    let router = &*router;

    let path_bytes = slice::from_raw_parts(path as *const u8, path_len);
    let path_str = match std::str::from_utf8(path_bytes) {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let host_str = if host.is_null() || host_len == 0 {
        None
    } else {
        let host_bytes = slice::from_raw_parts(host as *const u8, host_len);
        std::str::from_utf8(host_bytes).ok()
    };

    // Zero-initialize the output.
    (*result).handler = 0;
    (*result).params = ptr::null_mut();
    (*result).param_count = 0;
    (*result).match_type = 0;

    match router.match_route(host_str, path_str, method) {
        Some(m) => {
            (*result).handler = m.handler;
            (*result).match_type = m.match_type;

            if !m.params.is_empty() {
                let count = m.params.len();
                let mut c_params: Vec<NyroRouterParam> = Vec::with_capacity(count);

                for p in &m.params {
                    c_params.push(NyroRouterParam {
                        name: alloc_bytes(p.name.as_bytes()),
                        value: alloc_bytes(p.value.as_bytes()),
                        name_len: p.name.len(),
                        value_len: p.value.len(),
                    });
                }

                let mut boxed = c_params.into_boxed_slice();
                (*result).params = boxed.as_mut_ptr();
                (*result).param_count = count as c_int;
                std::mem::forget(boxed);
            }

            1
        }
        None => 0,
    }
}

/// Free the params array inside a match result.
///
/// Safe to call with NULL params or zero count.
#[no_mangle]
pub unsafe extern "C" fn nyro_router_match_result_free(result: *mut NyroRouterMatchResult) {
    if result.is_null() {
        return;
    }

    let params = (*result).params;
    let count = (*result).param_count as usize;

    if !params.is_null() && count > 0 {
        let param_slice = slice::from_raw_parts(params, count);
        for p in param_slice {
            dealloc_bytes(p.name as *mut u8, p.name_len);
            dealloc_bytes(p.value as *mut u8, p.value_len);
        }
        // Free the params array itself.
        let raw = ptr::slice_from_raw_parts_mut(params, count);
        let _ = Box::from_raw(raw);
    }

    (*result).params = ptr::null_mut();
    (*result).param_count = 0;
}

/// Return the total number of routes.
#[no_mangle]
pub unsafe extern "C" fn nyro_router_count(router: *mut Router) -> usize {
    if router.is_null() {
        return 0;
    }
    (*router).count()
}

/// Remove all routes and reset the router.
#[no_mangle]
pub unsafe extern "C" fn nyro_router_clear(router: *mut Router) {
    if !router.is_null() {
        (*router).clear();
    }
}
