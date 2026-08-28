use std::collections::HashSet;
use std::path::PathBuf;

use vsa_agent_contracts::*;
use vsa_ard::*;
use vsa_foundation::Id;
use vsa_vertex_bridge::*;

use vsa_mothership::{
    AutonomousMissionConfig, MissionCommandCatalog, RealAgentRunSpec, run_autonomous_mission_loop,
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

fn fixture_manifest() -> String {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join("autonomous_real_voyage")
        .join("Cargo.toml")
        .to_string_lossy()
        .into_owned()
}

fn fixture_cwd() -> String {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join("autonomous_real_voyage")
        .to_string_lossy()
        .into_owned()
}

fn build_run() -> RealAgentRunSpec {
    RealAgentRunSpec {
        mission_id: "mission-build".into(),
        program: "cargo".into(),
        args: vec!["build".into(), "--manifest-path".into(), fixture_manifest()],
        cwd: fixture_cwd(),
        capability: "RUN_BUILD".into(),
    }
}

fn test_run() -> RealAgentRunSpec {
    RealAgentRunSpec {
        mission_id: "mission-test".into(),
        program: "cargo".into(),
        args: vec!["test".into(), "--manifest-path".into(), fixture_manifest()],
        cwd: fixture_cwd(),
        capability: "RUN_TEST".into(),
    }
}

#[cfg(windows)]
fn vve_run() -> RealAgentRunSpec {
    RealAgentRunSpec {
        mission_id: "mission-vve".into(),
        program: "cmd".into(),
        args: vec!["/C".into(), "echo VERTEX_VVE_REAL_PROCESS_OK".into()],
        cwd: fixture_cwd(),
        capability: "RUN_VVE".into(),
    }
}

#[cfg(not(windows))]
fn vve_run() -> RealAgentRunSpec {
    RealAgentRunSpec {
        mission_id: "mission-vve".into(),
        program: "sh".into(),
        args: vec!["-c".into(), "printf VERTEX_VVE_REAL_PROCESS_OK".into()],
        cwd: fixture_cwd(),
        capability: "RUN_VVE".into(),
    }
}

#[test]
fn autonomous_real_voyage_build_test_vve_completed() {
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
        "agent-voyager",
        vec![
            DockCapability::Build,
            DockCapability::Test,
            DockCapability::VveValidate,
        ],
    );

    let session = start_fleet_controller_session(vec![build, test, vve], vec![agent])
        .expect("real voyage must launch");

    let original_session = session.session_id.clone();

    let mut commands = MissionCommandCatalog::new();

    commands.insert(build_run()).unwrap();
    commands.insert(test_run()).unwrap();
    commands.insert(vve_run()).unwrap();

    // ============================================================
    // ONE CALL.
    //
    // From this point the Mothership must autonomously perform:
    //
    // BUILD real process
    // -> Genesis
    // -> Dock
    // -> ARD
    // -> TEST
    // -> Genesis
    // -> Dock
    // -> ARD
    // -> VVE
    // -> Genesis
    // -> Dock
    // -> ARD
    // -> Completed
    // ============================================================

    let report = run_autonomous_mission_loop(
        session,
        &mut commands,
        AutonomousMissionConfig { max_waves: 3 },
    )
    .expect("autonomous real voyage must reach Completed");

    assert_eq!(report.initial_session_id, original_session);

    assert_eq!(report.wave_count(), 3);

    assert_eq!(
        report.terminal_status(),
        FleetControllerSessionStatus::Completed
    );

    assert_eq!(report.final_session.completed_waves, 3);

    let sequence = report
        .waves
        .iter()
        .map(|wave| wave.mission_ids.clone())
        .collect::<Vec<_>>();

    assert_eq!(
        sequence,
        vec![
            vec!["mission-build".to_string()],
            vec!["mission-test".to_string()],
            vec!["mission-vve".to_string()],
        ]
    );

    let wave_ids = report
        .waves
        .iter()
        .map(|wave| wave.wave_id.clone())
        .collect::<HashSet<_>>();

    assert_eq!(wave_ids.len(), 3);

    let dispatch_ids = report
        .waves
        .iter()
        .map(|wave| wave.dispatch_id.clone())
        .collect::<HashSet<_>>();

    assert_eq!(dispatch_ids.len(), 3);

    for wave in &report.waves {
        assert_eq!(wave.process_results.len(), 1);

        let process = &wave.process_results[0];

        assert!(
            process.success,
            "machine process failed: mission={} exit={:?} stderr={}",
            process.mission_id, process.exit_code, process.stderr
        );

        assert_eq!(process.exit_code, Some(0));

        assert_eq!(wave.emitted_event_count, 1);
    }

    assert_eq!(report.waves[0].process_results[0].program, "cargo");

    assert!(
        report.waves[0].process_results[0]
            .args
            .iter()
            .any(|arg| arg == "build")
    );

    assert_eq!(report.waves[1].process_results[0].program, "cargo");

    assert!(
        report.waves[1].process_results[0]
            .args
            .iter()
            .any(|arg| arg == "test")
    );

    assert!(
        report.waves[2].process_results[0]
            .stdout
            .contains("VERTEX_VVE_REAL_PROCESS_OK")
    );

    assert!(report.final_session.current_wave.dispatch.is_none());
}
