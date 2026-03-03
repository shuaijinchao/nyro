use anyhow::Result;
use serde_json::Value;

use crate::protocol::{IngressDecoder, Protocol};
use crate::protocol::types::*;
use super::types::*;

pub struct OpenAIDecoder;

impl IngressDecoder for OpenAIDecoder {
    fn decode_request(&self, body: Value) -> Result<InternalRequest> {
        let req: OpenAIRequest = serde_json::from_value(body)?;

        let messages = req
            .messages
            .into_iter()
            .map(decode_message)
            .collect::<Result<Vec<_>>>()?;

        Ok(InternalRequest {
            messages,
            model: req.model,
            stream: req.stream,
            temperature: req.temperature,
            max_tokens: req.max_tokens,
            top_p: req.top_p,
            tools: req.tools,
            tool_choice: req.tool_choice,
            source_protocol: Protocol::OpenAI,
            extra: req.extra,
        })
    }
}

fn decode_message(msg: OpenAIMessage) -> Result<InternalMessage> {
    let role = match msg.role.as_str() {
        "system" => Role::System,
        "user" => Role::User,
        "assistant" => Role::Assistant,
        "tool" => Role::Tool,
        other => anyhow::bail!("unknown role: {other}"),
    };

    let content = match msg.content {
        Some(OpenAIContent::Text(t)) => MessageContent::Text(t),
        Some(OpenAIContent::Parts(parts)) => {
            let blocks = parts
                .into_iter()
                .map(|p| match p {
                    OpenAIContentPart::Text { text } => ContentBlock::Text { text },
                    OpenAIContentPart::ImageUrl { image_url } => ContentBlock::Image {
                        source: ImageSource {
                            media_type: "image/url".to_string(),
                            data: image_url.url,
                        },
                    },
                })
                .collect();
            MessageContent::Blocks(blocks)
        }
        None => MessageContent::Text(String::new()),
    };

    Ok(InternalMessage {
        role,
        content,
        tool_calls: msg.tool_calls,
        tool_call_id: msg.tool_call_id,
    })
}
