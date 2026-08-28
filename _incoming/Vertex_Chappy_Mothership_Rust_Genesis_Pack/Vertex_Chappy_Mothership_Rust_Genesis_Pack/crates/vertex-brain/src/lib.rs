use anyhow::{anyhow, Context, Result};
use reqwest::blocking::{Client, RequestBuilder};
use serde::{Deserialize, Serialize};
use std::{env, time::Duration};

pub const DEFAULT_LM_STUDIO_BASE_URL: &str = "http://127.0.0.1:1234/v1";

#[derive(Debug, Clone)]
pub struct LmStudioClient {
    base_url: String,
    api_key: Option<String>,
    http: Client,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelInfo {
    pub id: String,
}

#[derive(Debug, Deserialize)]
struct ModelsResponse {
    data: Vec<ModelInfo>,
}

#[derive(Debug, Serialize)]
struct ChatRequest<'a> {
    model: &'a str,
    messages: Vec<ChatMessage<'a>>,
    temperature: f32,
    stream: bool,
}

#[derive(Debug, Serialize)]
struct ChatMessage<'a> {
    role: &'a str,
    content: &'a str,
}

#[derive(Debug, Deserialize)]
struct ChatResponse {
    choices: Vec<ChatChoice>,
}

#[derive(Debug, Deserialize)]
struct ChatChoice {
    message: ChatResponseMessage,
}

#[derive(Debug, Deserialize)]
struct ChatResponseMessage {
    content: Option<String>,
}

impl LmStudioClient {
    pub fn from_env() -> Result<Self> {
        let base_url = env::var("VERTEX_LM_STUDIO_BASE_URL")
            .unwrap_or_else(|_| DEFAULT_LM_STUDIO_BASE_URL.to_owned());

        let api_key = env::var("VERTEX_LM_STUDIO_API_KEY")
            .ok()
            .filter(|value| !value.trim().is_empty());

        Self::new(base_url, api_key)
    }

    pub fn new(base_url: impl Into<String>, api_key: Option<String>) -> Result<Self> {
        let base_url = base_url.into().trim_end_matches('/').to_owned();

        let http = Client::builder()
            .timeout(Duration::from_secs(600))
            .build()
            .context("build LM Studio HTTP client")?;

        Ok(Self {
            base_url,
            api_key,
            http,
        })
    }

    pub fn base_url(&self) -> &str {
        &self.base_url
    }

    fn authorize(&self, request: RequestBuilder) -> RequestBuilder {
        match &self.api_key {
            Some(api_key) => request.bearer_auth(api_key),
            None => request,
        }
    }

    pub fn list_models(&self) -> Result<Vec<ModelInfo>> {
        let url = format!("{}/models", self.base_url);

        let response = self
            .authorize(self.http.get(&url))
            .send()
            .with_context(|| format!("connect to LM Studio: {url}"))?
            .error_for_status()
            .with_context(|| format!("LM Studio returned an error: {url}"))?;

        let payload: ModelsResponse = response
            .json()
            .context("decode LM Studio /models response")?;

        Ok(payload.data)
    }

    pub fn has_model(&self, model_id: &str) -> Result<bool> {
        Ok(self.list_models()?.iter().any(|model| model.id == model_id))
    }

    pub fn chat(&self, model: &str, system: &str, user: &str, temperature: f32) -> Result<String> {
        let url = format!("{}/chat/completions", self.base_url);

        let body = ChatRequest {
            model,
            messages: vec![
                ChatMessage {
                    role: "system",
                    content: system,
                },
                ChatMessage {
                    role: "user",
                    content: user,
                },
            ],
            temperature,
            stream: false,
        };

        let response = self
            .authorize(self.http.post(&url))
            .json(&body)
            .send()
            .with_context(|| format!("LM Studio chat request failed for model {model}"))?
            .error_for_status()
            .with_context(|| format!("LM Studio rejected chat request for model {model}"))?;

        let payload: ChatResponse = response.json().context("decode LM Studio chat response")?;

        payload
            .choices
            .into_iter()
            .next()
            .and_then(|choice| choice.message.content)
            .ok_or_else(|| anyhow!("LM Studio returned no message content"))
    }
}
