use std::path::PathBuf;

use vsa_agent_contracts::*;
use vsa_ard::*;
use vsa_foundation::Id;
use vsa_vertex_bridge::*;

use vsa_mothership::{
    AutonomousMissionConfig, HyperAgentMission, HyperAgentWorkspace, MissionCommandCatalog,
    OllamaProviderSpec, REAL_HYPER_AGENT_RUNTIME_SCHEMA, RealAgentRunSpec,
    execute_real_hyper_agent_pipeline,
};

fn sample_work_unit() -> WorkUnit {
    WorkUnit {
        id: Id("mission-1".into()),
        parent: None,
        title: "Implement local brain bridge".into(),
        depends_on: vec![],
        state: MissionState::Ready,
        contract: ExecutionContract {
            role: "Developer".into(),
            scope: vec!["VVE".into(), "ARD".into()],
            forbidden: vec!["Bypass Human Gate".into()],
            stop_conditions: vec!["current reproducible blocker".into()],
        },
    }
}

fn sample_context() -> PreparedArdContext {
    PreparedArdContext {
        context_id: Id("ctx-1".into()),
        mission_id: Id("mission-1".into()),
        canon_refs: vec!["canon://vertex".into()],
        project_refs: vec!["project://vertex-studio".into()],
        repository_refs: vec!["repo://mothership".into()],
        memory_refs: vec!["memory://relevant/1".into()],
        vcc_refs: vec!["vcc://stream/1".into()],
        vsp_refs: vec!["vsp://current".into()],
        impact_refs: vec!["impact://mission/1".into()],
        evidence_refs: vec![],
        constraints: vec!["preserve human intent".into()],
        forbidden: vec!["silent scope expansion".into()],
        stop_conditions: vec!["current reproducible blocker".into()],
        context_version: "1".into(),
    }
}

fn sample_agent() -> HyperAgentAttachment {
    HyperAgentAttachment {
        identity: HyperAgentIdentity {
            id: Id("agent-1".into()),
            name: "Hyper Agent".into(),
            character: "Vertex Hyper Agent".into(),
            role: "Developer".into(),
            memory_refs: vec![],
            experience_refs: vec![],
        },
        brain: BrainCartridge {
            provider: "LM Studio".into(),
            model: "qwen3-coder-30b-a3b-instruct".into(),
            endpoint: Some("http://127.0.0.1:1234/v1".into()),
            context_window: Some(32768),
            temperature: Some(0.15),
        },
        vessel: VesselBinding {
            vessel_id: "mothership-1".into(),
            kind: VesselKind::Mothership,
            workspace: "project://vertex-studio/mothership".into(),
            connected: true,
        },
        grant: CapabilityGrant {
            agent_id: Id("agent-1".into()),
            vessel_id: "mothership-1".into(),
            allowed: vec![
                DockCapability::Build,
                DockCapability::Test,
                DockCapability::VveWrite,
                DockCapability::ImpactRead,
            ],
            maximum_risk: "medium".into(),
            human_gate_required_for: vec![DockCapability::VvePromote],
        },
        context: Some(sample_context()),
    }
}

fn fleet_agent(id: &str, capabilities: Vec<DockCapability>) -> HyperAgentAttachment {
    let mut agent = sample_agent();

    agent.identity.id = Id(id.into());
    agent.identity.name = id.into();
    agent.grant.agent_id = Id(id.into());
    agent.grant.allowed = capabilities;

    agent
}

fn fleet_mission(
    mission_id: &str,
    required_capability: DockCapability,
    verification: Vec<VerificationRequirement>,
) -> FleetMissionSpec {
    let mut unit = sample_work_unit();
    unit.id = Id(mission_id.into());
    unit.title = format!("Fleet mission {mission_id}");

    let mut context = sample_context();
    context.context_id = Id(format!("ctx-{mission_id}"));
    context.mission_id = Id(mission_id.into());

    FleetMissionSpec {
        unit,
        context,
        required_capability,
        verification,
    }
}

fn workspace_root() -> String {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join("real_hyper_agent_voyage")
        .to_string_lossy()
        .into_owned()
}

fn fixture_manifest() -> String {
    PathBuf::from(workspace_root())
        .join("Cargo.toml")
        .to_string_lossy()
        .into_owned()
}

fn build_run() -> RealAgentRunSpec {
    RealAgentRunSpec {
        mission_id: "mission-build".into(),
        program: "cargo".into(),
        args: vec!["build".into(), "--manifest-path".into(), fixture_manifest()],
        cwd: workspace_root(),
        capability: "RUN_BUILD".into(),
    }
}

fn test_run() -> RealAgentRunSpec {
    RealAgentRunSpec {
        mission_id: "mission-test".into(),
        program: "cargo".into(),
        args: vec!["test".into(), "--manifest-path".into(), fixture_manifest()],
        cwd: workspace_root(),
        capability: "RUN_TEST".into(),
    }
}

#[cfg(windows)]
fn vve_run() -> RealAgentRunSpec {
    RealAgentRunSpec {
        mission_id: "mission-vve".into(),
        program: "cmd".into(),
        args: vec![
            "/C".into(),
            "findstr /C:\"VERTEX_HYPER_AGENT_OK\" src\\lib.rs".into(),
        ],
        cwd: workspace_root(),
        capability: "RUN_VVE".into(),
    }
}

#[cfg(not(windows))]
fn vve_run() -> RealAgentRunSpec {
    RealAgentRunSpec {
        mission_id: "mission-vve".into(),
        program: "sh".into(),
        args: vec!["-c".into(), "grep VERTEX_HYPER_AGENT_OK src/lib.rs".into()],
        cwd: workspace_root(),
        capability: "RUN_VVE".into(),
    }
}

#[test]
#[ignore = "requires live Ollama qwen3:8b"]
fn real_hyper_agent_v2_full_voyage() {
    let build = fleet_mission(
        "mission-build",
        DockCapability::Build,
        vec![VerificationRequirement::Build],
    );

    let mut test = fleet_mission(
        "mission-test",
        DockCapability::Test,
        vec![VerificationRequirement::Test],
    );

    test.unit.depends_on = vec![Id("mission-build".into())];

    let mut vve = fleet_mission("mission-vve", DockCapability::VveValidate, vec![]);

    vve.unit.depends_on = vec![Id("mission-test".into())];

    let agent = fleet_agent(
        "agent-qwen-real",
        vec![
            DockCapability::Build,
            DockCapability::Test,
            DockCapability::VveValidate,
        ],
    );

    let session = start_fleet_controller_session(vec![build, test, vve], vec![agent])
        .expect("controller must launch");

    let mut catalog = MissionCommandCatalog::new();

    catalog.insert(build_run()).unwrap();
    catalog.insert(test_run()).unwrap();
    catalog.insert(vve_run()).unwrap();

    let provider = OllamaProviderSpec {
        endpoint: "http://127.0.0.1:11434/api/generate".into(),

        model: "qwen3:8b".into(),

        timeout_ms: 180_000,
    };

    let workspace = HyperAgentWorkspace {
        root: workspace_root(),
    };

    let mission = HyperAgentMission {
        mission_id: "hyper-agent-author".into(),

        target_relative_path: "src/lib.rs".into(),

        instruction: r#"
Create a complete Rust library.

It must define exactly this public function signature:

pub fn vertex_hyper_agent_probe() -> &'static str

It must return exactly:

VERTEX_HYPER_AGENT_OK

Add a cfg(test) module with one test verifying the exact return value.

Use no external crates.
"#
        .trim()
        .into(),
    };

    let report = execute_real_hyper_agent_pipeline(
        session,
        &mut catalog,
        AutonomousMissionConfig { max_waves: 3 },
        &provider,
        &workspace,
        &mission,
    )
    .expect("real qwen Hyper Agent must complete voyage");

    assert_eq!(report.schema, REAL_HYPER_AGENT_RUNTIME_SCHEMA);

    assert!(report.provider.success);

    assert!(!report.provider.timed_out);

    assert_eq!(report.provider.exit_code, Some(0));

    assert!(report.write.bytes_written > 0);

    assert_eq!(report.voyage.wave_count(), 3);

    assert_eq!(
        report.voyage.terminal_status(),
        FleetControllerSessionStatus::Completed
    );

    assert_eq!(report.voyage.final_session.completed_waves, 3);

    let generated =
        std::fs::read_to_string(PathBuf::from(workspace_root()).join("src").join("lib.rs"))
            .unwrap();

    assert!(generated.contains("VERTEX_HYPER_AGENT_OK"));

    assert!(!generated.contains("VERTEX_OLD_WORKSPACE"));
}
