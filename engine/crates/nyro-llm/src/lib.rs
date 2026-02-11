//! NYRO LLM — thin wrapper over `llm_converter` for synchronous protocol conversion.
//!
//! Exposes simple `convert_request` / `convert_response` functions that accept
//! protocol name strings and raw bytes, returning converted bytes or an error.

use llm_converter::{Converter, LlmConverter, Protocol};
use std::str::FromStr;

/// Convert an LLM request body from one protocol to another.
///
/// `from` / `to` are protocol name strings (e.g. `"openai_chat"`, `"anthropic_messages"`).
/// `input` is the raw JSON body bytes.
pub fn convert_request(from: &str, to: &str, input: &[u8]) -> Result<Vec<u8>, String> {
    let from_proto =
        Protocol::from_str(from).map_err(|e| format!("invalid source protocol: {e}"))?;
    let to_proto =
        Protocol::from_str(to).map_err(|e| format!("invalid target protocol: {e}"))?;

    let converter = LlmConverter::default();
    converter
        .convert_chat_request(from_proto, to_proto, input)
        .map_err(|e| format!("request conversion failed: {e}"))
}

/// Convert an LLM response body from one protocol to another.
///
/// Works for both full (non-streaming) responses and individual SSE `data:` payloads.
pub fn convert_response(from: &str, to: &str, input: &[u8]) -> Result<Vec<u8>, String> {
    let from_proto =
        Protocol::from_str(from).map_err(|e| format!("invalid source protocol: {e}"))?;
    let to_proto =
        Protocol::from_str(to).map_err(|e| format!("invalid target protocol: {e}"))?;

    let converter = LlmConverter::default();
    converter
        .convert_chat_response(from_proto, to_proto, input)
        .map_err(|e| format!("response conversion failed: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_invalid_protocol() {
        let r = convert_request("foo_bar", "openai_chat", b"{}");
        assert!(r.is_err());
        assert!(r.unwrap_err().contains("invalid source protocol"));
    }

    #[test]
    fn test_cross_category_rejected() {
        // chat -> embeddings should fail
        let r = convert_request("openai_chat", "openai_embeddings", b"{}");
        assert!(r.is_err());
    }
}
