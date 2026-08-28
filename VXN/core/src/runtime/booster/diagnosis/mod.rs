use serde::{Deserialize, Serialize};

use crate::runtime::adaptive::observer::RuntimeObservation;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum BoosterDiagnosis {
    Healthy,
    PromptBloat,
    SchemaInstability,
    LockScopeFailure,
    MemoryStarved,
    ModelStarved,
    Overpowered,
    ParallelBenefit,
    HighRisk,
}

pub struct BoosterDiagnoser;

impl BoosterDiagnoser {
    pub fn diagnose(observation: &RuntimeObservation) -> Vec<BoosterDiagnosis> {
        let mut out = Vec::new();

        if !observation.json_valid || observation.schema_completeness < 1.0 {
            out.push(BoosterDiagnosis::SchemaInstability);
        }

        if observation.lock_awareness < 1.0 || observation.scope_awareness < 1.0 {
            out.push(BoosterDiagnosis::LockScopeFailure);
        }

        if observation.prompt_tokens.unwrap_or(0) > 2500 && observation.schema_completeness < 1.0 {
            out.push(BoosterDiagnosis::PromptBloat);
        }

        if observation.retry_count >= 2 {
            out.push(BoosterDiagnosis::ModelStarved);
        }

        if out.is_empty() {
            out.push(BoosterDiagnosis::Healthy);
        }

        out
    }
}
