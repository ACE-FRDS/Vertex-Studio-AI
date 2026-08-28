use serde::{Deserialize, Serialize};

use super::state::ThrottleChannels;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeMap {
    pub mission_class: String,
    pub channels: ThrottleChannels,
}

impl RuntimeMap {
    pub fn general() -> Self {
        Self {
            mission_class: "GENERAL".into(),
            channels: ThrottleChannels {
                cognitive: 50,
                memory: 35,
                toolbox: 45,
                compute: 45,
                authority: 25,
                parallelism: 20,
            },
        }
    }
}
