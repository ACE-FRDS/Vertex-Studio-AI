use serde::{Deserialize, Serialize};

use super::observer::{RuntimeDiagnosis, RuntimeObservation};
use super::toolbox::{RuntimeToolbox, ToolboxComponent};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeDecision {
    pub toolbox: RuntimeToolbox,
    pub model_tier_delta: i32,
    pub reason: Vec<String>,
}

pub struct RuntimeComposer;

impl RuntimeComposer {
    pub fn compose(
        observation: &RuntimeObservation,
        diagnosis: &[RuntimeDiagnosis],
        current: &RuntimeToolbox,
    ) -> RuntimeDecision {
        let mut next = current.clone();
        let mut tier_delta = 0;
        let mut reason = Vec::new();

        for d in diagnosis {
            match d {
                RuntimeDiagnosis::LockScopeFailure => {
                    next.attach(ToolboxComponent::LockScope);
                    reason.push("Attach LockScope guard.".into());
                }
                RuntimeDiagnosis::MemoryRecallFailure => {
                    next.attach(ToolboxComponent::VccVsp);
                    next.attach(ToolboxComponent::ImpactAssociation);
                    reason.push("Expand memory/association boundary.".into());
                }
                RuntimeDiagnosis::AuthorityFailure => {
                    next.attach(ToolboxComponent::CandidateVtc);
                    reason.push("Attach Candidate/VTC authority boundary.".into());
                }
                RuntimeDiagnosis::PromptBloat => {
                    next.detach(&ToolboxComponent::Rag);
                    reason.push("Detach RAG due to prompt bloat.".into());
                }
                RuntimeDiagnosis::ModelTooSmall => {
                    tier_delta = 1;
                    reason.push("Escalate one model tier.".into());
                }
                RuntimeDiagnosis::ModelTooLarge => {
                    tier_delta = -1;
                    reason.push("De-escalate one model tier.".into());
                }
                RuntimeDiagnosis::ResourcePressure => {
                    next.detach(&ToolboxComponent::Rag);
                    reason.push("Shrink toolbox under resource pressure.".into());
                }
                _ => {}
            }
        }

        if observation.schema_completeness >= 1.0
            && observation.lock_awareness >= 1.0
            && observation.scope_awareness >= 1.0
            && observation.authority_awareness >= 1.0
        {
            reason.push("Current runtime satisfies core reliability signals.".into());
        }

        RuntimeDecision {
            toolbox: next,
            model_tier_delta: tier_delta,
            reason,
        }
    }
}
