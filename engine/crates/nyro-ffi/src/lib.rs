//! NYRO FFI — single cdylib exporting all native modules.
//!
//! Each sub-module exposes `#[no_mangle] extern "C"` functions that LuaJIT
//! calls via FFI. Adding a new native capability only requires adding a
//! new module here and a corresponding Lua cdef file.

pub mod llm;
pub mod router;
