use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum Capability {
    ReadMothershipState,
    ReadVur,
    QueryArd,
    GitInspect,
    RunBuild,
    RunTest,
    RunPowershellSafe,
    CreateVveChangeset,
    WriteVveFile,
    PromoteVve,
}

impl Capability {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::ReadMothershipState => "READ_MOTHERSHIP_STATE",
            Self::ReadVur => "READ_VUR",
            Self::QueryArd => "QUERY_ARD",
            Self::GitInspect => "GIT_INSPECT",
            Self::RunBuild => "RUN_BUILD",
            Self::RunTest => "RUN_TEST",
            Self::RunPowershellSafe => "RUN_POWERSHELL_SAFE",
            Self::CreateVveChangeset => "CREATE_VVE_CHANGESET",
            Self::WriteVveFile => "WRITE_VVE_FILE",
            Self::PromoteVve => "PROMOTE_VVE",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MissionRequest {
    pub capability: Capability,
    #[serde(default)]
    pub payload: Value,
    #[serde(default)]
    pub actor: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MissionEnvelope {
    pub mission_id: String,
    pub capability: Capability,
    pub actor: String,
    pub created_at: DateTime<Utc>,
    pub state: MissionState,
    pub payload: Value,
    pub result: Option<Value>,
}

impl MissionEnvelope {
    pub fn new(req: MissionRequest) -> Self {
        Self {
            mission_id: format!("mission://{}", Uuid::new_v4()),
            capability: req.capability,
            actor: req.actor.unwrap_or_else(|| "owner".into()),
            created_at: Utc::now(),
            state: MissionState::Accepted,
            payload: req.payload,
            result: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum MissionState {
    Accepted,
    Completed,
    Denied,
    Failed,
    HumanGateRequired,
}

#[derive(Debug, Error)]
pub enum VertexError {
    #[error("capability denied: {0}")]
    CapabilityDenied(String),
    #[error("human gate required: {0}")]
    HumanGateRequired(String),
    #[error("invalid request: {0}")]
    InvalidRequest(String),
    #[error("io: {0}")]
    Io(String),
    #[error("execution failed: {0}")]
    Execution(String),
}
