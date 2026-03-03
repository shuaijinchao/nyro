pub mod types;
pub mod openai;
pub mod anthropic;
pub mod gemini;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Protocol {
    OpenAI,
    Anthropic,
    Gemini,
}

impl std::fmt::Display for Protocol {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Protocol::OpenAI => write!(f, "openai"),
            Protocol::Anthropic => write!(f, "anthropic"),
            Protocol::Gemini => write!(f, "gemini"),
        }
    }
}

impl std::str::FromStr for Protocol {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "openai" => Ok(Protocol::OpenAI),
            "anthropic" => Ok(Protocol::Anthropic),
            "gemini" => Ok(Protocol::Gemini),
            _ => anyhow::bail!("unknown protocol: {s}"),
        }
    }
}

pub trait IngressDecoder {
    fn decode_request(&self, body: serde_json::Value) -> anyhow::Result<types::InternalRequest>;
}

pub trait EgressEncoder {
    fn encode_request(
        &self,
        req: &types::InternalRequest,
    ) -> anyhow::Result<(serde_json::Value, reqwest::header::HeaderMap)>;
}

pub trait ResponseTranscoder {
    fn transcode_response(
        &self,
        resp: serde_json::Value,
    ) -> anyhow::Result<(serde_json::Value, types::TokenUsage)>;

    fn stream_transcoder(&self) -> Box<dyn StreamTranscoder + Send>;
}

pub trait StreamTranscoder: Send {
    fn process_chunk(&mut self, chunk: &str) -> anyhow::Result<Vec<SseEvent>>;
    fn finish(&mut self) -> anyhow::Result<Vec<SseEvent>>;
    fn usage(&self) -> types::TokenUsage;
}

#[derive(Debug, Clone)]
pub struct SseEvent {
    pub event: Option<String>,
    pub data: String,
}

impl SseEvent {
    pub fn new(event: Option<&str>, data: impl Into<String>) -> Self {
        Self {
            event: event.map(|e| e.to_string()),
            data: data.into(),
        }
    }

    pub fn to_sse_string(&self) -> String {
        let mut s = String::new();
        if let Some(ref event) = self.event {
            s.push_str(&format!("event: {event}\n"));
        }
        s.push_str(&format!("data: {}\n\n", self.data));
        s
    }
}
