use serde::{Deserialize, Serialize};

use crate::runtime::adaptive::{
    composer::RuntimeComposer,
    observer::{RuntimeDiagnosis, RuntimeObservation},
    toolbox::{RuntimeToolbox, ToolboxComponent},
};

use super::diagnosis::BoosterDiagnosis;
use super::state::{BoosterMode, BoosterState};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BoosterDecision {
    pub next_state: BoosterState,
    pub toolbox: RuntimeToolbox,
    pub reasons: Vec<String>,
}

pub struct BoosterController;

impl BoosterController {
    pub fn apply(
        observation: &RuntimeObservation,
        booster_diagnosis: &[BoosterDiagnosis],
        current_state: &BoosterState,
        current_toolbox: &RuntimeToolbox,
    ) -> BoosterDecision {
        let mut state = current_state.clone();
        let mut toolbox = current_toolbox.clone();
        let mut reasons = Vec::new();

        for diagnosis in booster_diagnosis {
            match diagnosis {
                BoosterDiagnosis::Healthy => {
                    if state.master_throttle > 35 {
                        state.master_throttle = state.master_throttle.saturating_sub(10);
                        reasons.push("Healthy: reduce throttle toward efficient cruise.".into());
                    }
                }

                BoosterDiagnosis::SchemaInstability => {
                    state.channels.toolbox = state.channels.toolbox.saturating_add(15).min(100);
                    reasons.push("Schema instability: increase toolbox channel.".into());
                }

                BoosterDiagnosis::LockScopeFailure => {
                    toolbox.attach(ToolboxComponent::LockScope);
                    state.channels.toolbox = state.channels.toolbox.saturating_add(20).min(100);
                    state.hot_swap_count += 1;
                    reasons.push("Hot-swap LockScope guard.".into());
                }

                BoosterDiagnosis::MemoryStarved => {
                    toolbox.attach(ToolboxComponent::VccVsp);
                    toolbox.attach(ToolboxComponent::ImpactAssociation);
                    state.channels.memory = state.channels.memory.saturating_add(25).min(100);
                    state.hot_swap_count += 1;
                    reasons.push("Expand memory boundary and attach recall tools.".into());
                }

                BoosterDiagnosis::ModelStarved => {
                    state.model_tier_delta = 1;
                    state.channels.cognitive = state.channels.cognitive.saturating_add(20).min(100);
                    reasons.push("Escalate one model tier.".into());
                }

                BoosterDiagnosis::Overpowered => {
                    state.model_tier_delta = -1;
                    state.master_throttle = state.master_throttle.saturating_sub(15);
                    reasons.push("De-escalate model and reduce throttle.".into());
                }

                BoosterDiagnosis::ParallelBenefit => {
                    state.channels.parallelism =
                        state.channels.parallelism.saturating_add(25).min(100);
                    reasons.push("Increase parallelism; ARD party recommended.".into());
                }

                BoosterDiagnosis::HighRisk => {
                    toolbox.attach(ToolboxComponent::CandidateVtc);
                    state.channels.authority = state.channels.authority.saturating_sub(15);
                    state.hot_swap_count += 1;
                    reasons.push(
                        "High risk: attach Candidate/VTC while reducing authority throttle.".into(),
                    );
                }

                BoosterDiagnosis::PromptBloat => {
                    toolbox.detach(&ToolboxComponent::Rag);
                    state.channels.memory = state.channels.memory.saturating_sub(15);
                    state.channels.toolbox = state.channels.toolbox.saturating_sub(10);
                    state.hot_swap_count += 1;
                    reasons.push("Prompt bloat: detach RAG and shrink runtime boundary.".into());
                }
            }
        }

        state.master_throttle = Self::derive_master(&state);

        state.mode = match state.master_throttle {
            0..=15 => BoosterMode::Idle,
            16..=35 => BoosterMode::Eco,
            36..=65 => BoosterMode::Cruise,
            66..=90 => BoosterMode::Performance,
            _ => BoosterMode::Boost,
        };

        BoosterDecision {
            next_state: state,
            toolbox,
            reasons,
        }
    }

    fn derive_master(state: &BoosterState) -> u8 {
        let sum = state.channels.cognitive as u32
            + state.channels.memory as u32
            + state.channels.toolbox as u32
            + state.channels.compute as u32
            + state.channels.authority as u32
            + state.channels.parallelism as u32;

        (sum / 6).min(100) as u8
    }

    pub fn bridge_to_adaptive_runtime(
        observation: &RuntimeObservation,
        current_toolbox: &RuntimeToolbox,
    ) -> crate::runtime::adaptive::composer::RuntimeDecision {
        let mut diagnoses = Vec::new();

        if !observation.json_valid || observation.schema_completeness < 1.0 {
            diagnoses.push(RuntimeDiagnosis::SchemaDrift);
        }

        if observation.lock_awareness < 1.0 || observation.scope_awareness < 1.0 {
            diagnoses.push(RuntimeDiagnosis::LockScopeFailure);
        }

        RuntimeComposer::compose(observation, &diagnoses, current_toolbox)
    }
}
