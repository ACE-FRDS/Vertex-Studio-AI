use vsa_foundation::Id;

/// Persistent Hyper Agent identity.
///
/// The identity belongs to Vertex, not to the currently attached LLM.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HyperAgentIdentity {
    pub id: Id,
    pub name: String,
    pub character: String,
    pub role: String,
    pub memory_refs: Vec<String>,
    pub experience_refs: Vec<String>,
}

/// Replaceable reasoning engine attached to an Agent.
#[derive(Debug, Clone, PartialEq)]
pub struct BrainCartridge {
    pub provider: String,
    pub model: String,
    pub endpoint: Option<String>,
    pub context_window: Option<u64>,
    pub temperature: Option<f32>,
}

/// The vessel/environment currently hosting an Agent.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VesselKind {
    Mothership,
    Portable,
    Simulator,
    RemoteNode,
}

/// Binding between an Agent and its current vessel.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VesselBinding {
    pub vessel_id: String,
    pub kind: VesselKind,
    pub workspace: String,
    pub connected: bool,
}

/// Capability exposed through the Dock.
///
/// Agents receive capabilities rather than unrestricted access to the vessel.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum DockCapability {
    EditorRead,
    EditorWrite,

    VveRead,
    VveWrite,
    VveValidate,
    VvePromote,

    RepositoryRead,
    RepositoryWrite,

    GitRead,
    GitWrite,
    GitRemote,

    WarehouseRead,
    WarehouseWrite,

    MemoryRead,
    MemoryWrite,

    ImpactRead,

    RuntimeExecute,
    Build,
    Test,

    ObservatoryRead,
    EvidenceWrite,

    ArchiveCreate,
    ArchiveExtract,

    HumanGateRequest,
}

/// Effective capability grant for one Agent session.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapabilityGrant {
    pub agent_id: Id,
    pub vessel_id: String,
    pub allowed: Vec<DockCapability>,
    pub maximum_risk: String,
    pub human_gate_required_for: Vec<DockCapability>,
}

/// Context assembled by Vertex before an ARD stage begins.
///
/// Agents should not be expected to discover mandatory context themselves.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreparedArdContext {
    pub context_id: Id,
    pub mission_id: Id,

    pub canon_refs: Vec<String>,
    pub project_refs: Vec<String>,
    pub repository_refs: Vec<String>,

    pub memory_refs: Vec<String>,
    pub vcc_refs: Vec<String>,
    pub vsp_refs: Vec<String>,

    pub impact_refs: Vec<String>,
    pub evidence_refs: Vec<String>,

    pub constraints: Vec<String>,
    pub forbidden: Vec<String>,
    pub stop_conditions: Vec<String>,

    pub context_version: String,
}

/// One machine-observed process execution.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunObservation {
    pub program: String,
    pub args: Vec<String>,
    pub cwd: String,

    pub exit_code: Option<i32>,
    pub timed_out: bool,

    pub stdout_ref: Option<String>,
    pub stderr_ref: Option<String>,
}

impl RunObservation {
    pub fn passed(&self) -> bool {
        !self.timed_out && self.exit_code == Some(0)
    }
}

/// Evidence generated from actual system observation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EvidenceRecord {
    pub id: Id,
    pub mission_id: Id,
    pub source: String,
    pub kind: String,
    pub status: String,
    pub reference: String,
    pub summary: String,
}

/// What the system actually observed during Agent execution.
///
/// This is deliberately separate from an LLM narrative response.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActualExecutionObservation {
    pub mission_id: Id,
    pub agent_id: Id,

    pub changed_files: Vec<String>,
    pub runs: Vec<RunObservation>,
    pub evidence: Vec<EvidenceRecord>,

    pub blocker: Option<String>,
    pub scope_violations: u32,
    pub human_interventions: u32,

    pub duration_ms: u64,
}

/// Event emitted by the common Dock/Event fabric.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DockEvent {
    pub sequence: u64,
    pub mission_id: Option<Id>,
    pub agent_id: Option<Id>,

    pub source: String,
    pub channel: String,
    pub severity: String,
    pub kind: String,

    pub object_ref: Option<String>,
    pub evidence_ref: Option<String>,

    pub message: String,
}

/// Complete runtime attachment of one Hyper Agent.
#[derive(Debug, Clone, PartialEq)]
pub struct HyperAgentAttachment {
    pub identity: HyperAgentIdentity,
    pub brain: BrainCartridge,
    pub vessel: VesselBinding,
    pub grant: CapabilityGrant,
    pub context: Option<PreparedArdContext>,
}

impl HyperAgentAttachment {
    /// Brain replacement must not replace Agent identity or experience.
    pub fn replace_brain(&mut self, brain: BrainCartridge) {
        self.brain = brain;
    }

    pub fn has_capability(&self, capability: &DockCapability) -> bool {
        self.grant.allowed.contains(capability)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn identity() -> HyperAgentIdentity {
        HyperAgentIdentity {
            id: Id("agent-hyper-1".into()),
            name: "Hyper Agent".into(),
            character: "Vertex Hyper Agent".into(),
            role: "Developer".into(),
            memory_refs: vec!["memory://agent/hyper-1".into()],
            experience_refs: vec!["experience://mission/previous".into()],
        }
    }

    fn brain(model: &str) -> BrainCartridge {
        BrainCartridge {
            provider: "LM Studio".into(),
            model: model.into(),
            endpoint: Some("http://127.0.0.1:1234/v1".into()),
            context_window: Some(32768),
            temperature: Some(0.15),
        }
    }

    fn vessel(kind: VesselKind) -> VesselBinding {
        VesselBinding {
            vessel_id: "vertex-vessel-1".into(),
            kind,
            workspace: "project://vertex-studio/mothership".into(),
            connected: true,
        }
    }

    fn grant() -> CapabilityGrant {
        CapabilityGrant {
            agent_id: Id("agent-hyper-1".into()),
            vessel_id: "vertex-vessel-1".into(),
            allowed: vec![
                DockCapability::EditorRead,
                DockCapability::VveWrite,
                DockCapability::RepositoryRead,
                DockCapability::ImpactRead,
                DockCapability::Build,
                DockCapability::Test,
            ],
            maximum_risk: "medium".into(),
            human_gate_required_for: vec![DockCapability::VvePromote],
        }
    }

    #[test]
    fn brain_can_change_without_replacing_agent_identity() {
        let mut attachment = HyperAgentAttachment {
            identity: identity(),
            brain: brain("qwen3-coder-30b-a3b-instruct"),
            vessel: vessel(VesselKind::Mothership),
            grant: grant(),
            context: None,
        };

        let original_id = attachment.identity.id.clone();
        let original_memory = attachment.identity.memory_refs.clone();

        attachment.replace_brain(brain("google/gemma-4-31b-qat"));

        assert_eq!(attachment.identity.id, original_id);
        assert_eq!(attachment.identity.memory_refs, original_memory);
        assert_eq!(attachment.brain.model, "google/gemma-4-31b-qat");
    }

    #[test]
    fn hyper_agent_can_bind_to_portable() {
        let binding = vessel(VesselKind::Portable);

        assert_eq!(binding.kind, VesselKind::Portable);
        assert!(binding.connected);
    }

    #[test]
    fn dock_capability_is_explicit() {
        let attachment = HyperAgentAttachment {
            identity: identity(),
            brain: brain("qwen3-coder-30b-a3b-instruct"),
            vessel: vessel(VesselKind::Mothership),
            grant: grant(),
            context: None,
        };

        assert!(attachment.has_capability(&DockCapability::Build));
        assert!(attachment.has_capability(&DockCapability::ImpactRead));
        assert!(!attachment.has_capability(&DockCapability::VvePromote));
    }

    #[test]
    fn prepared_context_contains_memory_and_impact() {
        let context = PreparedArdContext {
            context_id: Id("ctx-1".into()),
            mission_id: Id("mission-1".into()),

            canon_refs: vec!["canon://vertex".into()],
            project_refs: vec!["project://vertex-studio".into()],
            repository_refs: vec!["repo://mothership".into()],

            memory_refs: vec!["memory://relevant/1".into()],
            vcc_refs: vec!["vcc://stream/1".into()],
            vsp_refs: vec!["vsp://current".into()],

            impact_refs: vec!["impact://mission/1".into()],
            evidence_refs: vec!["evidence://previous/1".into()],

            constraints: vec!["preserve human intent".into()],
            forbidden: vec!["silent scope expansion".into()],
            stop_conditions: vec!["current reproducible blocker".into()],

            context_version: "1".into(),
        };

        assert!(!context.memory_refs.is_empty());
        assert!(!context.impact_refs.is_empty());
        assert!(!context.canon_refs.is_empty());
    }

    #[test]
    fn run_observation_uses_machine_exit_status() {
        let success = RunObservation {
            program: "cargo".into(),
            args: vec!["test".into(), "--workspace".into()],
            cwd: "G:\\Vertex_Project\\Vertex_Studio_AI".into(),
            exit_code: Some(0),
            timed_out: false,
            stdout_ref: Some("evidence://stdout/1".into()),
            stderr_ref: None,
        };

        assert!(success.passed());

        let failure = RunObservation {
            exit_code: Some(101),
            ..success
        };

        assert!(!failure.passed());
    }

    #[test]
    fn evidence_is_bound_to_mission() {
        let evidence = EvidenceRecord {
            id: Id("evidence-1".into()),
            mission_id: Id("mission-1".into()),
            source: "vertex-runtime".into(),
            kind: "build".into(),
            status: "PASS".into(),
            reference: "evidence://build/1".into(),
            summary: "cargo build --workspace --release exited 0".into(),
        };

        assert_eq!(evidence.mission_id.0, "mission-1");
        assert_eq!(evidence.status, "PASS");
    }
}
