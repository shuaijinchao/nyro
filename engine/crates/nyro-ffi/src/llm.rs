//! FFI exports for LLM protocol conversion.
//!
//! All functions follow the pattern:
//!   - Accept raw pointers + lengths for strings/bytes
//!   - Write output to caller-provided `*mut *mut u8` / `*mut usize`
//!   - Return 0 on success, negative on error
//!   - Caller must free output via `nyro_llm_free`

use std::os::raw::c_int;
use std::slice;
use std::str;

// ── Return codes ────────────────────────────────────────────────────────────

const NYRO_LLM_OK: c_int = 0;
const NYRO_LLM_ERR_PROTOCOL: c_int = -1;
const NYRO_LLM_ERR_CONVERT: c_int = -2;
const NYRO_LLM_ERR_INVALID: c_int = -3;

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Convert a raw (ptr, len) pair to a `&str`. Returns `None` on null / invalid UTF-8.
unsafe fn ptr_to_str<'a>(ptr: *const u8, len: usize) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    let bytes = slice::from_raw_parts(ptr, len);
    str::from_utf8(bytes).ok()
}

/// Write a `Vec<u8>` result into the caller's out-pointers.
/// Ownership is transferred; caller must call `nyro_llm_free` later.
unsafe fn write_output(data: Vec<u8>, out: *mut *mut u8, out_len: *mut usize) {
    let len = data.len();
    let boxed = data.into_boxed_slice();
    let ptr = Box::into_raw(boxed) as *mut u8;
    *out = ptr;
    *out_len = len;
}

/// Write an error string into the caller's out-pointers (for diagnostics).
unsafe fn write_error(msg: &str, out: *mut *mut u8, out_len: *mut usize) {
    let data = msg.as_bytes().to_vec();
    write_output(data, out, out_len);
}

// ── Public FFI ──────────────────────────────────────────────────────────────

/// Convert an LLM chat request body between protocols.
///
/// # Parameters
/// - `from` / `from_len`: source protocol name (e.g. `"openai_chat"`)
/// - `to` / `to_len`: target protocol name
/// - `input` / `input_len`: raw JSON body
/// - `out` / `out_len`: receives the converted body on success, or error message on failure
///
/// # Returns
/// `0` on success, negative error code on failure.
#[no_mangle]
pub unsafe extern "C" fn nyro_llm_convert_request(
    from: *const u8,
    from_len: usize,
    to: *const u8,
    to_len: usize,
    input: *const u8,
    input_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    // Validate pointers
    if out.is_null() || out_len.is_null() {
        return NYRO_LLM_ERR_INVALID;
    }

    let from_str = match ptr_to_str(from, from_len) {
        Some(s) => s,
        None => {
            write_error("invalid from protocol pointer", out, out_len);
            return NYRO_LLM_ERR_PROTOCOL;
        }
    };

    let to_str = match ptr_to_str(to, to_len) {
        Some(s) => s,
        None => {
            write_error("invalid to protocol pointer", out, out_len);
            return NYRO_LLM_ERR_PROTOCOL;
        }
    };

    if input.is_null() {
        write_error("null input pointer", out, out_len);
        return NYRO_LLM_ERR_INVALID;
    }

    let input_bytes = slice::from_raw_parts(input, input_len);

    match nyro_llm::convert_request(from_str, to_str, input_bytes) {
        Ok(result) => {
            write_output(result, out, out_len);
            NYRO_LLM_OK
        }
        Err(e) => {
            write_error(&e, out, out_len);
            if e.contains("invalid") && e.contains("protocol") {
                NYRO_LLM_ERR_PROTOCOL
            } else {
                NYRO_LLM_ERR_CONVERT
            }
        }
    }
}

/// Convert an LLM chat response body between protocols.
///
/// Same signature and semantics as `nyro_llm_convert_request`.
#[no_mangle]
pub unsafe extern "C" fn nyro_llm_convert_response(
    from: *const u8,
    from_len: usize,
    to: *const u8,
    to_len: usize,
    input: *const u8,
    input_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    if out.is_null() || out_len.is_null() {
        return NYRO_LLM_ERR_INVALID;
    }

    let from_str = match ptr_to_str(from, from_len) {
        Some(s) => s,
        None => {
            write_error("invalid from protocol pointer", out, out_len);
            return NYRO_LLM_ERR_PROTOCOL;
        }
    };

    let to_str = match ptr_to_str(to, to_len) {
        Some(s) => s,
        None => {
            write_error("invalid to protocol pointer", out, out_len);
            return NYRO_LLM_ERR_PROTOCOL;
        }
    };

    if input.is_null() {
        write_error("null input pointer", out, out_len);
        return NYRO_LLM_ERR_INVALID;
    }

    let input_bytes = slice::from_raw_parts(input, input_len);

    match nyro_llm::convert_response(from_str, to_str, input_bytes) {
        Ok(result) => {
            write_output(result, out, out_len);
            NYRO_LLM_OK
        }
        Err(e) => {
            write_error(&e, out, out_len);
            if e.contains("invalid") && e.contains("protocol") {
                NYRO_LLM_ERR_PROTOCOL
            } else {
                NYRO_LLM_ERR_CONVERT
            }
        }
    }
}

/// Free a buffer previously returned by `nyro_llm_convert_request` or
/// `nyro_llm_convert_response`.
#[no_mangle]
pub unsafe extern "C" fn nyro_llm_free(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    // Reconstruct the Box<[u8]> and drop it
    let _ = Box::from_raw(slice::from_raw_parts_mut(ptr, len));
}
