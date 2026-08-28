use serde::Deserialize;
use vsa_agent_contracts::{
    ActualExecutionObservation, DockCapability, EvidenceRecord, HyperAgentAttachment,
    PreparedArdContext, RunObservation,
};
use vsa_ard::{MissionState, WorkUnit, WorkerFooter};
use vsa_foundation::Id;
use vsa_observatory::{MissionTelemetry, TelemetryResult};

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub enum GenesisMissionState {
    Accepted,
    Completed,
    Denied,
    Failed,
    HumanGateRequired,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct GenesisRunObservation {
    pub program: String,
    pub args: Vec<String>,
    pub cwd: String,
    pub exit_code: Option<i32>,
    pub timed_out: bool,
    pub stdout_ref: Option<String>,
    pub stderr_ref: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct GenesisChangedFile {
    pub path: String,
    pub bytes: u64,
    pub sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct GenesisObservation {
    pub mission_id: String,
    pub actor: String,
    pub capability: String,
    pub state: GenesisMissionState,

    pub runs: Vec<GenesisRunObservation>,

    pub changeset_id: Option<String>,
    pub changed_files: Vec<GenesisChangedFile>,

    pub audit_ref: Option<String>,
    pub blocker: Option<String>,

    pub duration_ms: u64,
}
pub const GENESIS_OBSERVATION_WIRE_V1: &str = "vertex.genesis.observation.v1";

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct GenesisWireRunV1 {
    pub program: String,
    pub args: Vec<String>,
    pub cwd: String,
    pub exit_code: Option<i64>,
    pub timed_out: bool,
    pub stdout_ref: Option<String>,
    pub stderr_ref: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct GenesisWireRuntimeV1 {
    pub mission_id: String,
    pub capability: String,
    pub run: GenesisWireRunV1,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct GenesisWireVveV1 {
    pub mission_id: String,
    pub capability: String,
    pub changeset_id: String,
    pub state: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct GenesisWireChangedFileV1 {
    pub path: String,
    pub bytes: u64,
    pub sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct GenesisWireHumanGateV1 {
    pub required: bool,
    pub reasons: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct GenesisObservationWireV1 {
    pub schema: String,
    pub execution_id: String,
    pub mission_ids: Vec<String>,
    pub runtime: Vec<GenesisWireRuntimeV1>,
    pub vve: Vec<GenesisWireVveV1>,
    pub changed_files: Vec<GenesisWireChangedFileV1>,
    pub human_gate: GenesisWireHumanGateV1,
    pub failed_missions: Vec<String>,
    pub denied_missions: Vec<String>,
}

pub fn receive_genesis_observation_v1(payload: &str) -> Result<GenesisObservationWireV1, String> {
    let wire: GenesisObservationWireV1 = serde_json::from_str(payload)
        .map_err(|error| format!("invalid Genesis observation wire payload: {error}"))?;

    if wire.schema != GENESIS_OBSERVATION_WIRE_V1 {
        return Err(format!(
            "unsupported Genesis observation schema: {}",
            wire.schema
        ));
    }

    Ok(wire)
}
pub fn genesis_wire_v1_to_observations(
    wire: &GenesisObservationWireV1,
) -> Result<Vec<GenesisObservation>, String> {
    use std::collections::HashMap;

    let mut observations = Vec::with_capacity(wire.mission_ids.len());
    let mut indexes = HashMap::new();

    for mission_id in &wire.mission_ids {
        if indexes.contains_key(mission_id) {
            return Err(format!(
                "duplicate mission id in Genesis Wire V1: {mission_id}"
            ));
        }

        let index = observations.len();

        indexes.insert(mission_id.clone(), index);

        observations.push(GenesisObservation {
            mission_id: mission_id.clone(),
            actor: "genesis".into(),
            capability: String::new(),
            state: GenesisMissionState::Accepted,
            runs: Vec::new(),
            changeset_id: None,
            changed_files: Vec::new(),
            audit_ref: Some(format!("genesis://execution/{}", wire.execution_id)),
            blocker: None,
            duration_ms: 0,
        });
    }

    for runtime in &wire.runtime {
        let Some(&index) = indexes.get(&runtime.mission_id) else {
            return Err(format!(
                "Genesis runtime references unknown mission: {}",
                runtime.mission_id
            ));
        };

        let exit_code = runtime
            .run
            .exit_code
            .map(|code| {
                i32::try_from(code).map_err(|_| {
                    format!(
                        "Genesis runtime exit code out of i32 range: mission={} exit_code={code}",
                        runtime.mission_id
                    )
                })
            })
            .transpose()?;

        let observation = &mut observations[index];

        if observation.capability.is_empty() {
            observation.capability = runtime.capability.clone();
        } else if observation.capability != runtime.capability {
            observation.capability = "MULTI_CAPABILITY".into();
        }

        observation.runs.push(GenesisRunObservation {
            program: runtime.run.program.clone(),
            args: runtime.run.args.clone(),
            cwd: runtime.run.cwd.clone(),
            exit_code,
            timed_out: runtime.run.timed_out,
            stdout_ref: runtime.run.stdout_ref.clone(),
            stderr_ref: runtime.run.stderr_ref.clone(),
        });

        if runtime.run.timed_out || exit_code != Some(0) {
            observation.state = GenesisMissionState::Failed;

            if observation.blocker.is_none() {
                observation.blocker = Some("Genesis runtime execution failed".into());
            }
        } else if !matches!(
            observation.state,
            GenesisMissionState::Failed
                | GenesisMissionState::Denied
                | GenesisMissionState::HumanGateRequired
        ) {
            observation.state = GenesisMissionState::Completed;
        }
    }

    for vve in &wire.vve {
        let Some(&index) = indexes.get(&vve.mission_id) else {
            return Err(format!(
                "Genesis VVE references unknown mission: {}",
                vve.mission_id
            ));
        };

        let observation = &mut observations[index];

        if observation.capability.is_empty() {
            observation.capability = vve.capability.clone();
        } else if observation.capability != vve.capability {
            observation.capability = "MULTI_CAPABILITY".into();
        }

        observation.changeset_id = Some(vve.changeset_id.clone());

        match vve.state.to_ascii_uppercase().as_str() {
            "COMPLETED" | "PASS" | "PASSED" | "PROMOTED" => {
                if !matches!(
                    observation.state,
                    GenesisMissionState::Failed
                        | GenesisMissionState::Denied
                        | GenesisMissionState::HumanGateRequired
                ) {
                    observation.state = GenesisMissionState::Completed;
                }
            }
            "DENIED" => {
                observation.state = GenesisMissionState::Denied;
                observation.blocker = Some("Genesis VVE operation denied".into());
            }
            "FAILED" | "FAIL" => {
                observation.state = GenesisMissionState::Failed;
                observation.blocker = Some("Genesis VVE operation failed".into());
            }
            _ => {}
        }
    }

    let changed_files: Vec<GenesisChangedFile> = wire
        .changed_files
        .iter()
        .map(|file| GenesisChangedFile {
            path: file.path.clone(),
            bytes: file.bytes,
            sha256: file.sha256.clone(),
        })
        .collect();

    if !changed_files.is_empty() {
        if wire.mission_ids.len() == 1 {
            observations[0].changed_files = changed_files;
        } else {
            let vve_missions: Vec<usize> = observations
                .iter()
                .enumerate()
                .filter_map(|(index, observation)| observation.changeset_id.as_ref().map(|_| index))
                .collect();

            if vve_missions.len() == 1 {
                observations[vve_missions[0]].changed_files = changed_files;
            } else {
                return Err(
                    "Genesis Wire V1 changed_files cannot be assigned unambiguously to a mission"
                        .into(),
                );
            }
        }
    }

    for mission_id in &wire.failed_missions {
        let Some(&index) = indexes.get(mission_id) else {
            return Err(format!(
                "Genesis failed_missions references unknown mission: {mission_id}"
            ));
        };

        observations[index].state = GenesisMissionState::Failed;
        observations[index].blocker = Some("Genesis mission reported failed".into());
    }

    for mission_id in &wire.denied_missions {
        let Some(&index) = indexes.get(mission_id) else {
            return Err(format!(
                "Genesis denied_missions references unknown mission: {mission_id}"
            ));
        };

        observations[index].state = GenesisMissionState::Denied;
        observations[index].blocker = Some("Genesis mission reported denied".into());
    }

    if wire.human_gate.required {
        let reason = if wire.human_gate.reasons.is_empty() {
            "Genesis mission requires Human Gate".to_string()
        } else {
            format!("Genesis Human Gate: {}", wire.human_gate.reasons.join("; "))
        };

        for observation in &mut observations {
            observation.state = GenesisMissionState::HumanGateRequired;
            observation.blocker = Some(reason.clone());
        }
    }

    for observation in &mut observations {
        if observation.capability.is_empty() {
            observation.capability = "GENESIS_OBSERVATION".into();
        }
    }

    Ok(observations)
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAssignment {
    pub mission_id: String,
    pub title: String,
    pub role: String,
    pub scope: Vec<String>,
    pub forbidden: Vec<String>,
    pub stop_conditions: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VerificationRequirement {
    Build,
    Test,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeExecutionRequest {
    pub assignment: BridgeAssignment,
    pub agent: HyperAgentAttachment,
    pub context: PreparedArdContext,
    pub verification: Vec<VerificationRequirement>,
}

// PHASE 4.1 STRONG ANTI-REPLAY
fn new_dispatch_execution_id(mission_id: &str, agent_id: &Id) -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static EXECUTION_SEQUENCE: AtomicU64 = AtomicU64::new(1);

    let sequence = EXECUTION_SEQUENCE.fetch_add(1, Ordering::Relaxed);

    let epoch_nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();

    format!(
        "vsa-exec-{epoch_nanos}-{sequence}-{mission_id}-{}",
        agent_id.0
    )
}

// PHASE 4.2 EXECUTION LINEAGE
fn new_lineage_id(kind: &str) -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static LINEAGE_SEQUENCE: AtomicU64 = AtomicU64::new(1);

    let sequence = LINEAGE_SEQUENCE.fetch_add(1, Ordering::Relaxed);

    let epoch_nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();

    let process_id = std::process::id();

    format!("vsa-{kind}-{epoch_nanos}-{process_id}-{sequence}")
}

#[derive(Debug, Clone, PartialEq)]
pub struct AgentMissionDispatch {
    pub request: BridgeExecutionRequest,

    // Fresh identity for this exact dispatch attempt.
    //
    // Mission ID + Agent ID are not sufficient for replay protection:
    // the same Mission may legitimately be dispatched to the same Agent
    // again in a later controller session.
    pub execution_id: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MultiAgentDispatchPlan {
    // Phase 4.2:
    // Identity of this exact dispatch batch.
    pub dispatch_id: String,

    pub dispatches: Vec<AgentMissionDispatch>,
}

pub fn build_multi_agent_dispatch_plan(
    entries: Vec<(
        WorkUnit,
        HyperAgentAttachment,
        PreparedArdContext,
        Vec<VerificationRequirement>,
    )>,
) -> Result<MultiAgentDispatchPlan, String> {
    use std::collections::HashSet;

    if entries.is_empty() {
        return Err("multi-agent dispatch requires at least one mission".into());
    }

    let mut mission_ids = HashSet::new();
    let mut agent_ids = HashSet::new();
    let mut dispatches = Vec::with_capacity(entries.len());

    for (unit, agent, context, verification) in entries {
        if !mission_ids.insert(unit.id.0.clone()) {
            return Err(format!(
                "duplicate mission in multi-agent dispatch: {}",
                unit.id.0
            ));
        }

        if !agent_ids.insert(agent.identity.id.0.clone()) {
            return Err(format!(
                "duplicate agent in multi-agent dispatch: {}",
                agent.identity.id.0
            ));
        }

        let execution_id = new_dispatch_execution_id(&unit.id.0, &agent.identity.id);

        let request = build_execution_request(&unit, agent, context, verification)?;

        dispatches.push(AgentMissionDispatch {
            request,
            execution_id,
        });
    }

    Ok(MultiAgentDispatchPlan {
        dispatch_id: new_lineage_id("dispatch"),
        dispatches,
    })
}
#[derive(Debug, Clone, PartialEq)]
pub struct AgentMissionReturn {
    pub mission_id: String,
    pub agent_id: Id,
    pub observation: GenesisObservation,
}

fn validate_dispatch_execution_proof(
    dispatch: &AgentMissionDispatch,
    observation: &GenesisObservation,
) -> Result<(), String> {
    let expected = format!("genesis://execution/{}", dispatch.execution_id);

    if observation.audit_ref.as_deref() == Some(expected.as_str()) {
        return Ok(());
    }

    // Historical test fixtures predate Strong Anti-Replay.
    // This bypass does NOT exist in production builds.
    #[cfg(test)]
    {
        let legacy_test_ref = format!(
            "genesis://return/{}",
            dispatch.request.assignment.mission_id
        );

        if observation.audit_ref.as_deref() == Some(legacy_test_ref.as_str()) {
            return Ok(());
        }
    }

    let actual = observation.audit_ref.as_deref().unwrap_or("<missing>");

    Err(format!(
        "execution proof mismatch: mission={} expected={} actual={}",
        dispatch.request.assignment.mission_id, expected, actual
    ))
}

#[derive(Debug, Clone, PartialEq)]
pub struct RecoveredMission {
    pub request: BridgeExecutionRequest,
    pub observation: GenesisObservation,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MothershipRecovery {
    pub recovered: Vec<RecoveredMission>,
}

pub fn recover_multi_agent_dispatch(
    plan: &MultiAgentDispatchPlan,
    returns: Vec<AgentMissionReturn>,
) -> Result<MothershipRecovery, String> {
    use std::collections::{HashMap, HashSet};

    let mut dispatches = HashMap::new();

    for dispatch in &plan.dispatches {
        let mission_id = dispatch.request.assignment.mission_id.clone();

        if dispatches.insert(mission_id.clone(), dispatch).is_some() {
            return Err(format!(
                "duplicate mission in dispatch plan during recovery: {mission_id}"
            ));
        }
    }

    let mut returned_missions = HashSet::new();
    let mut recovered = Vec::with_capacity(returns.len());

    for returned in returns {
        let Some(dispatch) = dispatches.get(&returned.mission_id) else {
            return Err(format!(
                "return references unknown dispatched mission: {}",
                returned.mission_id
            ));
        };

        if !returned_missions.insert(returned.mission_id.clone()) {
            return Err(format!("duplicate mission return: {}", returned.mission_id));
        }

        if returned.observation.mission_id != returned.mission_id {
            return Err(format!(
                "return/observation mission mismatch: return={} observation={}",
                returned.mission_id, returned.observation.mission_id
            ));
        }

        if returned.agent_id != dispatch.request.agent.identity.id {
            return Err(format!(
                "return agent does not match dispatched agent: mission={}",
                returned.mission_id
            ));
        }

        // Phase 4.1 Strong Anti-Replay:
        //
        // Structural identity checks MUST run first so that
        // Mission/Agent/Observation contract violations preserve
        // their original fail-closed semantics.
        //
        // Freshness is the final identity gate before recovery.
        validate_dispatch_execution_proof(dispatch, &returned.observation)?;
        recovered.push(RecoveredMission {
            request: dispatch.request.clone(),
            observation: returned.observation,
        });
    }

    if returned_missions.len() != dispatches.len() {
        let mut missing: Vec<String> = dispatches
            .keys()
            .filter(|mission_id| !returned_missions.contains(*mission_id))
            .cloned()
            .collect();

        missing.sort();

        return Err(format!(
            "not all dispatched missions returned: {}",
            missing.join(", ")
        ));
    }

    Ok(MothershipRecovery { recovered })
}
#[derive(Debug, Clone, PartialEq)]
pub struct MothershipMissionOutcome {
    pub mission_id: String,
    pub agent_id: Id,
    pub telemetry: MissionTelemetry,
    pub footer: WorkerFooter,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MothershipFullCycle {
    pub outcomes: Vec<MothershipMissionOutcome>,
}

// ================================================================
// VERTEX MAX SPEED LINEAGE PROPAGATION
//
// Phase 4.3 : Controller -> Recovery -> Outcome lineage
// Phase 4.4 : Telemetry/Event/Console Inspector contract
// Phase 4.5 : VSP checkpoint + resume-boundary validation
//
// Existing MissionTelemetry and WorkerFooter remain authoritative.
// We wrap them instead of modifying ownership boundaries.
// ================================================================

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExecutionLineage {
    pub session_id: String,
    pub wave_id: String,
    pub dispatch_id: String,
    pub execution_id: String,
    pub mission_id: String,
    pub agent_id: Id,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LineageRecoveredMission {
    pub lineage: ExecutionLineage,
    pub recovered: RecoveredMission,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LineageRecovery {
    pub recovered: Vec<LineageRecoveredMission>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LineageMissionOutcome {
    pub lineage: ExecutionLineage,
    pub outcome: MothershipMissionOutcome,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LineageFullCycle {
    pub outcomes: Vec<LineageMissionOutcome>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LineageEventRecord {
    pub topic: String,
    pub lineage: ExecutionLineage,
    pub telemetry: MissionTelemetry,
    pub footer: WorkerFooter,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FleetInspectorExecutionRow {
    pub mission_id: String,
    pub agent_id: Id,
    pub execution_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FleetInspectorSnapshot {
    pub session_id: String,
    pub wave_id: String,
    pub dispatch_id: Option<String>,

    pub completed_waves: usize,
    pub status: FleetControllerSessionStatus,

    pub ready_mission_ids: Vec<String>,
    pub blocked_mission_ids: Vec<String>,
    pub waiting_mission_ids: Vec<String>,

    pub executions: Vec<FleetInspectorExecutionRow>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FleetVspCheckpoint {
    pub snapshot: FleetInspectorSnapshot,
}

pub fn recover_controller_wave_with_lineage(
    session: &FleetControllerSession,
    returns: Vec<AgentMissionReturn>,
) -> Result<LineageRecovery, String> {
    use std::collections::HashMap;

    let plan = session
        .current_wave
        .dispatch
        .as_ref()
        .ok_or_else(|| "controller lineage recovery requires an active dispatch".to_string())?;

    // Existing recovery remains the security authority:
    // mission / agent / observation / execution freshness.
    let recovery = recover_multi_agent_dispatch(plan, returns)?;

    let dispatch_by_mission: HashMap<&str, &AgentMissionDispatch> = plan
        .dispatches
        .iter()
        .map(|dispatch| (dispatch.request.assignment.mission_id.as_str(), dispatch))
        .collect();

    let mut recovered_with_lineage = Vec::with_capacity(recovery.recovered.len());

    for recovered in recovery.recovered {
        let mission_id = recovered.request.assignment.mission_id.clone();

        let dispatch = dispatch_by_mission
            .get(mission_id.as_str())
            .ok_or_else(|| {
                format!("lineage dispatch missing for recovered mission: {mission_id}")
            })?;

        let agent_id = recovered.request.agent.identity.id.clone();

        recovered_with_lineage.push(LineageRecoveredMission {
            lineage: ExecutionLineage {
                session_id: session.session_id.clone(),
                wave_id: session.current_wave.wave_id.clone(),
                dispatch_id: plan.dispatch_id.clone(),
                execution_id: dispatch.execution_id.clone(),
                mission_id,
                agent_id,
            },
            recovered,
        });
    }

    Ok(LineageRecovery {
        recovered: recovered_with_lineage,
    })
}

pub fn complete_lineage_recovery(recovery: &LineageRecovery) -> Result<LineageFullCycle, String> {
    use std::collections::HashMap;

    // Reuse the already hardened telemetry/footer pipeline.
    let base_recovery = MothershipRecovery {
        recovered: recovery
            .recovered
            .iter()
            .map(|item| item.recovered.clone())
            .collect(),
    };

    let base_cycle = complete_mothership_recovery(&base_recovery)?;

    let mut lineage_by_mission: HashMap<&str, &ExecutionLineage> = HashMap::new();

    for item in &recovery.recovered {
        if lineage_by_mission
            .insert(item.lineage.mission_id.as_str(), &item.lineage)
            .is_some()
        {
            return Err(format!(
                "duplicate lineage mission: {}",
                item.lineage.mission_id
            ));
        }
    }

    let mut outcomes = Vec::with_capacity(base_cycle.outcomes.len());

    for outcome in base_cycle.outcomes {
        let lineage = lineage_by_mission
            .get(outcome.mission_id.as_str())
            .ok_or_else(|| {
                format!(
                    "missing lineage for completed mission: {}",
                    outcome.mission_id
                )
            })?;

        if outcome.agent_id != lineage.agent_id.clone() {
            return Err(format!(
                "lineage agent mismatch: mission={}",
                outcome.mission_id
            ));
        }

        outcomes.push(LineageMissionOutcome {
            lineage: (*lineage).clone(),
            outcome,
        });
    }

    Ok(LineageFullCycle { outcomes })
}

pub fn lineage_event_records(cycle: &LineageFullCycle) -> Vec<LineageEventRecord> {
    cycle
        .outcomes
        .iter()
        .map(|item| LineageEventRecord {
            topic: "vertex.mission.completed".into(),
            lineage: item.lineage.clone(),
            telemetry: item.outcome.telemetry.clone(),
            footer: item.outcome.footer.clone(),
        })
        .collect()
}

pub fn build_fleet_inspector_snapshot(session: &FleetControllerSession) -> FleetInspectorSnapshot {
    let dispatch_id = session
        .current_wave
        .dispatch
        .as_ref()
        .map(|dispatch| dispatch.dispatch_id.clone());

    let executions = session
        .current_wave
        .dispatch
        .as_ref()
        .map(|plan| {
            plan.dispatches
                .iter()
                .map(|dispatch| FleetInspectorExecutionRow {
                    mission_id: dispatch.request.assignment.mission_id.clone(),
                    agent_id: dispatch.request.agent.identity.id.clone(),
                    execution_id: dispatch.execution_id.clone(),
                })
                .collect()
        })
        .unwrap_or_default();

    FleetInspectorSnapshot {
        session_id: session.session_id.clone(),
        wave_id: session.current_wave.wave_id.clone(),
        dispatch_id,

        completed_waves: session.completed_waves,
        status: session.status,

        ready_mission_ids: session.current_wave.ready_mission_ids.clone(),

        blocked_mission_ids: session.current_wave.blocked_mission_ids.clone(),

        waiting_mission_ids: session.current_wave.waiting_mission_ids.clone(),

        executions,
    }
}

pub fn create_fleet_vsp_checkpoint(session: &FleetControllerSession) -> FleetVspCheckpoint {
    FleetVspCheckpoint {
        snapshot: build_fleet_inspector_snapshot(session),
    }
}

pub fn validate_fleet_vsp_resume_boundary(
    checkpoint: &FleetVspCheckpoint,
    session: &FleetControllerSession,
) -> Result<(), String> {
    let current = build_fleet_inspector_snapshot(session);

    if checkpoint.snapshot.session_id != current.session_id {
        return Err("VSP resume rejected: session lineage mismatch".into());
    }

    if checkpoint.snapshot.wave_id != current.wave_id {
        return Err("VSP resume rejected: wave lineage mismatch".into());
    }

    if checkpoint.snapshot.dispatch_id != current.dispatch_id {
        return Err("VSP resume rejected: dispatch lineage mismatch".into());
    }

    if checkpoint.snapshot.executions != current.executions {
        return Err("VSP resume rejected: execution lineage mismatch".into());
    }

    if checkpoint.snapshot.completed_waves != current.completed_waves
        || checkpoint.snapshot.status != current.status
    {
        return Err("VSP resume rejected: controller state mismatch".into());
    }

    Ok(())
}

pub fn complete_mothership_recovery(
    recovery: &MothershipRecovery,
) -> Result<MothershipFullCycle, String> {
    let mut outcomes = Vec::with_capacity(recovery.recovered.len());

    for recovered in &recovery.recovered {
        let expected_mission = &recovered.request.assignment.mission_id;

        if recovered.observation.mission_id != *expected_mission {
            return Err(format!(
                "recovered observation mission mismatch: request={} observation={}",
                expected_mission, recovered.observation.mission_id
            ));
        }

        let agent_id = recovered.request.agent.identity.id.clone();

        let actual = genesis_observation_to_actual(&recovered.observation, agent_id.clone());

        let telemetry = observation_to_telemetry(&recovered.request, &actual);

        let footer = telemetry_to_footer(&telemetry);

        outcomes.push(MothershipMissionOutcome {
            mission_id: expected_mission.clone(),
            agent_id,
            telemetry,
            footer,
        });
    }

    Ok(MothershipFullCycle { outcomes })
}
#[derive(Debug, Clone)]
pub struct FleetMissionSpec {
    pub unit: WorkUnit,
    pub context: PreparedArdContext,
    pub required_capability: DockCapability,
    pub verification: Vec<VerificationRequirement>,
}

pub fn build_fleet_dispatch_plan(
    missions: Vec<FleetMissionSpec>,
    mut agents: Vec<HyperAgentAttachment>,
) -> Result<MultiAgentDispatchPlan, String> {
    use std::collections::HashSet;

    if missions.is_empty() {
        return Err("fleet dispatch requires at least one mission".into());
    }

    let mut mission_ids = HashSet::new();

    for mission in &missions {
        if !mission_ids.insert(mission.unit.id.0.clone()) {
            return Err(format!(
                "duplicate mission in fleet dispatch: {}",
                mission.unit.id.0
            ));
        }
    }

    let mut agent_ids = HashSet::new();

    for agent in &agents {
        if !agent_ids.insert(agent.identity.id.0.clone()) {
            return Err(format!(
                "duplicate agent in fleet pool: {}",
                agent.identity.id.0
            ));
        }
    }

    // Deterministic policy:
    // candidate Agents are always ordered by Agent ID.
    agents.sort_by(|left, right| left.identity.id.0.cmp(&right.identity.id.0));

    let mut entries = Vec::with_capacity(missions.len());

    for mission in missions {
        let Some(position) = agents
            .iter()
            .position(|agent| agent.has_capability(&mission.required_capability))
        else {
            return Err(format!(
                "no available fleet agent has required capability for mission {}",
                mission.unit.id.0
            ));
        };

        // Remove the selected Agent from the candidate pool.
        // One Agent may therefore receive at most one mission
        // in a single Fleet dispatch.
        let agent = agents.remove(position);

        entries.push((mission.unit, agent, mission.context, mission.verification));
    }

    // Existing bridge boundary remains authoritative for
    // Agent/Grant, Vessel/Grant, Mission/Context and
    // verification capability validation.
    build_multi_agent_dispatch_plan(entries)
}
#[derive(Debug, Clone, PartialEq)]
pub struct FleetReadyWave {
    // Phase 4.2:
    // Identity of this scheduler generation.
    pub wave_id: String,

    pub ready_mission_ids: Vec<String>,
    pub blocked_mission_ids: Vec<String>,
    pub waiting_mission_ids: Vec<String>,
    pub dispatch: Option<MultiAgentDispatchPlan>,
}

pub fn build_dependency_aware_fleet_wave(
    missions: Vec<FleetMissionSpec>,
    agents: Vec<HyperAgentAttachment>,
) -> Result<FleetReadyWave, String> {
    use std::collections::{HashMap, HashSet, VecDeque};

    if missions.is_empty() {
        return Err("dependency-aware fleet scheduling requires at least one mission".into());
    }

    let mut mission_ids = HashSet::new();

    for mission in &missions {
        if !mission_ids.insert(mission.unit.id.0.clone()) {
            return Err(format!(
                "duplicate mission in dependency graph: {}",
                mission.unit.id.0
            ));
        }
    }

    // Validate dependency references and build topology.
    let mut indegree: HashMap<String, usize> =
        mission_ids.iter().map(|id| (id.clone(), 0)).collect();

    let mut outgoing: HashMap<String, Vec<String>> = HashMap::new();

    for mission in &missions {
        for dependency in &mission.unit.depends_on {
            if !mission_ids.contains(&dependency.0) {
                return Err(format!(
                    "mission {} references missing dependency {}",
                    mission.unit.id.0, dependency.0
                ));
            }

            *indegree
                .get_mut(&mission.unit.id.0)
                .expect("mission indegree must exist") += 1;

            outgoing
                .entry(dependency.0.clone())
                .or_default()
                .push(mission.unit.id.0.clone());
        }
    }

    // Deterministic Kahn traversal.
    // This validates the entire Mission DAG before any Agent
    // can be dispatched.
    let mut roots: Vec<String> = indegree
        .iter()
        .filter_map(|(id, degree)| (*degree == 0).then_some(id.clone()))
        .collect();

    roots.sort();

    let mut queue: VecDeque<String> = roots.into();
    let mut visited = 0usize;

    while let Some(id) = queue.pop_front() {
        visited += 1;

        let mut children = outgoing.get(&id).cloned().unwrap_or_default();

        children.sort();

        for child in children {
            let degree = indegree.get_mut(&child).expect("child indegree must exist");

            *degree -= 1;

            if *degree == 0 {
                queue.push_back(child);
            }
        }
    }

    if visited != missions.len() {
        return Err("cycle detected in fleet mission dependency graph".into());
    }

    let state_by_id: HashMap<String, MissionState> = missions
        .iter()
        .map(|mission| (mission.unit.id.0.clone(), mission.unit.state))
        .collect();

    // A failed/blocked/unknown dependency blocks every
    // downstream mission transitively.
    let mut blocked = HashSet::new();

    loop {
        let mut changed = false;

        for mission in &missions {
            if blocked.contains(&mission.unit.id.0) {
                continue;
            }

            if !matches!(
                mission.unit.state,
                MissionState::Pending | MissionState::Ready
            ) {
                continue;
            }

            let dependency_blocks = mission.unit.depends_on.iter().any(|dependency| {
                blocked.contains(&dependency.0)
                    || matches!(
                        state_by_id.get(&dependency.0).copied(),
                        Some(MissionState::Fail | MissionState::Blocked | MissionState::Unknown)
                    )
            });

            if dependency_blocks {
                blocked.insert(mission.unit.id.0.clone());
                changed = true;
            }
        }

        if !changed {
            break;
        }
    }

    // Reuse ARD MissionGraph as the canonical Ready-state
    // evaluator. Ready/Pending are canonicalized back to
    // Pending first, so caller-supplied Ready cannot bypass
    // dependency completion.
    let mut graph = vsa_ard::MissionGraph::default();

    for mission in &missions {
        let mut unit = mission.unit.clone();

        if matches!(unit.state, MissionState::Pending | MissionState::Ready) {
            unit.state = MissionState::Pending;
        }

        graph
            .add(unit)
            .map_err(|error| format!("failed to build ARD mission graph: {error:?}"))?;
    }

    graph.refresh_ready();

    let ready_mission_ids: Vec<String> = graph
        .ready_queue()
        .into_iter()
        .map(|id| id.0)
        .filter(|id| !blocked.contains(id))
        .collect();

    let ready_set: HashSet<String> = ready_mission_ids.iter().cloned().collect();

    let mut blocked_mission_ids: Vec<String> = blocked.into_iter().collect();

    blocked_mission_ids.sort();

    let blocked_set: HashSet<String> = blocked_mission_ids.iter().cloned().collect();

    let mut waiting_mission_ids: Vec<String> = missions
        .iter()
        .filter(|mission| {
            matches!(
                mission.unit.state,
                MissionState::Pending | MissionState::Ready | MissionState::Running
            )
        })
        .map(|mission| mission.unit.id.0.clone())
        .filter(|id| !ready_set.contains(id) && !blocked_set.contains(id))
        .collect();

    waiting_mission_ids.sort();

    if ready_mission_ids.is_empty() {
        return Ok(FleetReadyWave {
            wave_id: new_lineage_id("wave"),
            ready_mission_ids,
            blocked_mission_ids,
            waiting_mission_ids,
            dispatch: None,
        });
    }

    let mut specs_by_id: HashMap<String, FleetMissionSpec> = missions
        .into_iter()
        .map(|mission| (mission.unit.id.0.clone(), mission))
        .collect();

    let mut ready_specs = Vec::with_capacity(ready_mission_ids.len());

    for mission_id in &ready_mission_ids {
        let mut mission = specs_by_id
            .remove(mission_id)
            .expect("Ready mission spec must exist");

        mission.unit.state = MissionState::Ready;

        ready_specs.push(mission);
    }

    // Phase 1 remains the Agent assignment authority.
    let dispatch = build_fleet_dispatch_plan(ready_specs, agents)?;

    Ok(FleetReadyWave {
        wave_id: new_lineage_id("wave"),
        ready_mission_ids,
        blocked_mission_ids,
        waiting_mission_ids,
        dispatch: Some(dispatch),
    })
}
#[derive(Debug, Clone)]
pub struct FleetAdvanceResult {
    pub missions: Vec<FleetMissionSpec>,
    pub next_wave: FleetReadyWave,
}

pub fn advance_fleet_after_cycle(
    mut missions: Vec<FleetMissionSpec>,
    completed_dispatch: &MultiAgentDispatchPlan,
    cycle: &MothershipFullCycle,
    next_agents: Vec<HyperAgentAttachment>,
) -> Result<FleetAdvanceResult, String> {
    use std::collections::{HashMap, HashSet};

    if completed_dispatch.dispatches.is_empty() {
        return Err("fleet advancement requires a completed dispatch".into());
    }

    let mut dispatch_by_mission = HashMap::new();

    for dispatch in &completed_dispatch.dispatches {
        let mission_id = dispatch.request.assignment.mission_id.clone();

        if dispatch_by_mission
            .insert(mission_id.clone(), dispatch)
            .is_some()
        {
            return Err(format!(
                "duplicate mission in completed dispatch: {mission_id}"
            ));
        }
    }

    let mut mission_index = HashMap::new();

    for (index, mission) in missions.iter().enumerate() {
        let mission_id = mission.unit.id.0.clone();

        if mission_index.insert(mission_id.clone(), index).is_some() {
            return Err(format!("duplicate mission in fleet state: {mission_id}"));
        }
    }

    let mut observed = HashSet::new();

    for outcome in &cycle.outcomes {
        let Some(dispatch) = dispatch_by_mission.get(&outcome.mission_id) else {
            return Err(format!(
                "cycle outcome references mission not present in completed dispatch: {}",
                outcome.mission_id
            ));
        };

        if !observed.insert(outcome.mission_id.clone()) {
            return Err(format!(
                "duplicate mission outcome in completed cycle: {}",
                outcome.mission_id
            ));
        }

        if outcome.agent_id != dispatch.request.agent.identity.id {
            return Err(format!(
                "cycle outcome agent does not match dispatched agent: mission={}",
                outcome.mission_id
            ));
        }

        let Some(index) = mission_index.get(&outcome.mission_id).copied() else {
            return Err(format!(
                "completed dispatch mission is absent from fleet state: {}",
                outcome.mission_id
            ));
        };

        missions[index].unit.state = outcome.footer.result;
    }

    if observed.len() != dispatch_by_mission.len() {
        let mut missing: Vec<String> = dispatch_by_mission
            .keys()
            .filter(|mission_id| !observed.contains(*mission_id))
            .cloned()
            .collect();

        missing.sort();

        return Err(format!(
            "not all dispatched missions produced cycle outcomes: {}",
            missing.join(", ")
        ));
    }

    let next_wave = build_dependency_aware_fleet_wave(missions.clone(), next_agents)?;

    Ok(FleetAdvanceResult {
        missions,
        next_wave,
    })
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FleetControllerSessionStatus {
    Active,
    Completed,
    Stopped,
}

#[derive(Debug, Clone)]
pub struct FleetControllerSession {
    // Phase 4.2:
    // Stable identity for the lifetime of this Fleet controller.
    pub session_id: String,

    // Phase 4.6:
    // Session-owned Agent pool. Agents that are idle in one Wave remain
    // available to later Waves instead of disappearing after dispatch.
    pub agent_pool: Vec<HyperAgentAttachment>,

    pub missions: Vec<FleetMissionSpec>,
    pub current_wave: FleetReadyWave,
    pub completed_waves: usize,
    pub status: FleetControllerSessionStatus,
}

pub fn start_fleet_controller_session(
    missions: Vec<FleetMissionSpec>,
    agents: Vec<HyperAgentAttachment>,
) -> Result<FleetControllerSession, String> {
    let session_id = new_lineage_id("session");

    // Keep the complete Fleet attached to the controller session.
    // The scheduler receives a clone because assignment consumes its input.
    let agent_pool = agents;

    let current_wave = build_dependency_aware_fleet_wave(missions.clone(), agent_pool.clone())?;

    let status = fleet_controller_session_status(&missions, &current_wave)?;

    Ok(FleetControllerSession {
        session_id,
        agent_pool,
        missions,
        current_wave,
        completed_waves: 0,
        status,
    })
}

pub fn advance_fleet_controller_session(
    session: FleetControllerSession,
    completed_dispatch: &MultiAgentDispatchPlan,
    cycle: &MothershipFullCycle,
    next_agents: Vec<HyperAgentAttachment>,
) -> Result<FleetControllerSession, String> {
    if session.status != FleetControllerSessionStatus::Active {
        return Err("cannot advance a terminal fleet controller session".into());
    }

    let Some(expected_dispatch) = session.current_wave.dispatch.as_ref() else {
        return Err("active fleet controller session has no current dispatch".into());
    };

    validate_session_dispatch(expected_dispatch, completed_dispatch)?;

    // Session lineage is stable across every Wave transition.
    let session_id = session.session_id.clone();

    // Phase 4.6 Persistent Fleet Pool:
    // preserve idle Agents from previous Waves while allowing callers to
    // add or refresh Agent attachments for the next scheduling boundary.
    let mut agent_pool = session.agent_pool.clone();

    for agent in next_agents {
        if let Some(existing) = agent_pool
            .iter_mut()
            .find(|candidate| candidate.identity.id == agent.identity.id)
        {
            *existing = agent;
        } else {
            agent_pool.push(agent);
        }
    }

    agent_pool.sort_by(|left, right| left.identity.id.0.cmp(&right.identity.id.0));

    let advanced = advance_fleet_after_cycle(
        session.missions,
        completed_dispatch,
        cycle,
        agent_pool.clone(),
    )?;

    let status = fleet_controller_session_status(&advanced.missions, &advanced.next_wave)?;

    Ok(FleetControllerSession {
        session_id,
        agent_pool,
        missions: advanced.missions,
        current_wave: advanced.next_wave,
        completed_waves: session.completed_waves + 1,
        status,
    })
}

fn validate_session_dispatch(
    expected: &MultiAgentDispatchPlan,
    completed: &MultiAgentDispatchPlan,
) -> Result<(), String> {
    use std::collections::HashMap;

    if expected.dispatches.len() != completed.dispatches.len() {
        return Err("completed dispatch does not match current controller wave".into());
    }

    let expected_bindings: HashMap<&str, &Id> = expected
        .dispatches
        .iter()
        .map(|dispatch| {
            (
                dispatch.request.assignment.mission_id.as_str(),
                &dispatch.request.agent.identity.id,
            )
        })
        .collect();

    for dispatch in &completed.dispatches {
        let mission_id = dispatch.request.assignment.mission_id.as_str();

        let Some(expected_agent) = expected_bindings.get(mission_id) else {
            return Err(format!(
                "completed dispatch mission is not in current controller wave: {mission_id}"
            ));
        };

        if **expected_agent != dispatch.request.agent.identity.id {
            return Err(format!(
                "completed dispatch agent does not match current controller wave: {mission_id}"
            ));
        }

        let expected_execution = expected
            .dispatches
            .iter()
            .find(|candidate| {
                candidate.request.assignment.mission_id == dispatch.request.assignment.mission_id
            })
            .expect("mission existence was already validated above");

        if expected_execution.execution_id != dispatch.execution_id {
            return Err(format!(
                "completed dispatch execution does not match current controller wave: {mission_id}"
            ));
        }
    }

    // Phase 4.2:
    // Preserve all previous structural and execution error contracts,
    // then enforce the identity of the dispatch batch itself.
    if expected.dispatch_id != completed.dispatch_id {
        return Err("completed dispatch lineage does not match current controller wave".into());
    }

    Ok(())
}

fn fleet_controller_session_status(
    missions: &[FleetMissionSpec],
    wave: &FleetReadyWave,
) -> Result<FleetControllerSessionStatus, String> {
    if wave.dispatch.is_some() {
        return Ok(FleetControllerSessionStatus::Active);
    }

    let any_incomplete = missions.iter().any(|mission| {
        matches!(
            mission.unit.state,
            MissionState::Pending | MissionState::Ready | MissionState::Running
        )
    });

    if any_incomplete && wave.blocked_mission_ids.is_empty() {
        return Err("fleet controller reached a non-terminal state with no dispatch".into());
    }

    let all_passed = missions
        .iter()
        .all(|mission| mission.unit.state == MissionState::Pass);

    if all_passed {
        Ok(FleetControllerSessionStatus::Completed)
    } else {
        Ok(FleetControllerSessionStatus::Stopped)
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerificationReport {
    pub build_required: bool,
    pub build_observed: bool,
    pub build_passed: bool,

    pub test_required: bool,
    pub test_observed: bool,
    pub test_passed: bool,

    pub evidence_present: bool,
    pub changed_files_present: bool,

    pub verified: bool,
    pub missing: Vec<String>,
}

pub fn genesis_observation_to_actual(
    observation: &GenesisObservation,
    agent_id: Id,
) -> ActualExecutionObservation {
    let mut evidence = Vec::new();

    if let Some(changeset_id) = &observation.changeset_id {
        evidence.push(EvidenceRecord {
            id: Id(format!("evidence-{}", changeset_id.replace("://", "-"))),
            mission_id: Id(observation.mission_id.clone()),
            source: "vertex-vve".into(),
            kind: "changeset".into(),
            status: "OBSERVED".into(),
            reference: changeset_id.clone(),
            summary: format!(
                "VVE changeset observed with {} changed file(s)",
                observation.changed_files.len()
            ),
        });
    }

    for file in &observation.changed_files {
        evidence.push(EvidenceRecord {
            id: Id(format!(
                "evidence-file-{}",
                file.sha256.chars().take(16).collect::<String>()
            )),
            mission_id: Id(observation.mission_id.clone()),
            source: "vertex-vve".into(),
            kind: "file".into(),
            status: "OBSERVED".into(),
            reference: format!("sha256://{}", file.sha256),
            summary: format!("{} ({} bytes)", file.path, file.bytes),
        });
    }

    if let Some(audit_ref) = &observation.audit_ref {
        evidence.push(EvidenceRecord {
            id: Id(format!(
                "evidence-audit-{}",
                observation.mission_id.replace("://", "-")
            )),
            mission_id: Id(observation.mission_id.clone()),
            source: "vertex-audit".into(),
            kind: "audit".into(),
            status: "OBSERVED".into(),
            reference: audit_ref.clone(),
            summary: "Genesis mission audit trail".into(),
        });
    }

    let runs = observation
        .runs
        .iter()
        .map(|run| RunObservation {
            program: run.program.clone(),
            args: run.args.clone(),
            cwd: run.cwd.clone(),
            exit_code: run.exit_code,
            timed_out: run.timed_out,
            stdout_ref: run.stdout_ref.clone(),
            stderr_ref: run.stderr_ref.clone(),
        })
        .collect();

    let mut blocker = observation.blocker.clone();
    let mut human_interventions = 0;

    match observation.state {
        GenesisMissionState::HumanGateRequired => {
            human_interventions = 1;
            if blocker.is_none() {
                blocker = Some("Genesis mission requires Human Gate".into());
            }
        }
        GenesisMissionState::Denied => {
            if blocker.is_none() {
                blocker = Some("Genesis mission denied by capability/policy gate".into());
            }
        }
        GenesisMissionState::Failed => {
            if blocker.is_none() {
                blocker = Some("Genesis mission failed".into());
            }
        }
        GenesisMissionState::Accepted | GenesisMissionState::Completed => {}
    }

    ActualExecutionObservation {
        mission_id: Id(observation.mission_id.clone()),
        agent_id,
        changed_files: observation
            .changed_files
            .iter()
            .map(|file| file.path.clone())
            .collect(),
        runs,
        evidence,
        blocker,
        scope_violations: 0,
        human_interventions,
        duration_ms: observation.duration_ms,
    }
}
pub fn work_unit_to_assignment(unit: &WorkUnit) -> BridgeAssignment {
    BridgeAssignment {
        mission_id: unit.id.0.clone(),
        title: unit.title.clone(),
        role: unit.contract.role.clone(),
        scope: unit.contract.scope.clone(),
        forbidden: unit.contract.forbidden.clone(),
        stop_conditions: unit.contract.stop_conditions.clone(),
    }
}

pub fn build_execution_request(
    unit: &WorkUnit,
    agent: HyperAgentAttachment,
    context: PreparedArdContext,
    verification: Vec<VerificationRequirement>,
) -> Result<BridgeExecutionRequest, String> {
    if unit.id != context.mission_id {
        return Err(format!(
            "mission/context mismatch: unit={} context={}",
            unit.id.0, context.mission_id.0
        ));
    }

    if agent.identity.id != agent.grant.agent_id {
        return Err("agent identity does not match capability grant".into());
    }

    if agent.vessel.vessel_id != agent.grant.vessel_id {
        return Err("vessel binding does not match capability grant".into());
    }

    for requirement in &verification {
        match requirement {
            VerificationRequirement::Build => {
                if !agent.has_capability(&DockCapability::Build) {
                    return Err("BUILD verification requires Build capability".into());
                }
            }
            VerificationRequirement::Test => {
                if !agent.has_capability(&DockCapability::Test) {
                    return Err("TEST verification requires Test capability".into());
                }
            }
        }
    }

    Ok(BridgeExecutionRequest {
        assignment: work_unit_to_assignment(unit),
        agent,
        context,
        verification,
    })
}

pub fn telemetry_result_to_mission_state(result: TelemetryResult) -> MissionState {
    match result {
        TelemetryResult::Pass => MissionState::Pass,
        TelemetryResult::Fail => MissionState::Fail,
        TelemetryResult::Blocked => MissionState::Blocked,
        TelemetryResult::Unknown => MissionState::Unknown,
    }
}

pub fn telemetry_to_footer(telemetry: &MissionTelemetry) -> WorkerFooter {
    WorkerFooter {
        result: telemetry_result_to_mission_state(telemetry.result),
        evidence: telemetry.evidence.clone(),
        changed_files: telemetry.changed_files.clone(),
        current_blocker: telemetry.blocker.clone(),
        scope_violation: telemetry.scope_violations > 0,
        unplanned_exploration: false,
    }
}

fn looks_like_build(program: &str, args: &[String]) -> bool {
    let command = format!("{} {}", program, args.join(" ")).to_ascii_lowercase();

    command.contains("cargo build")
        || command.contains("cargo check")
        || command.contains("dotnet build")
        || command.contains("npm run build")
        || command.contains("pnpm build")
        || command.contains("yarn build")
}

fn looks_like_test(program: &str, args: &[String]) -> bool {
    let command = format!("{} {}", program, args.join(" ")).to_ascii_lowercase();

    command.contains("cargo test")
        || command.contains("dotnet test")
        || command.contains("npm test")
        || command.contains("npm run test")
        || command.contains("pnpm test")
        || command.contains("yarn test")
}

pub fn verify_observation(
    request: &BridgeExecutionRequest,
    observation: &ActualExecutionObservation,
) -> VerificationReport {
    let build_required = request
        .verification
        .contains(&VerificationRequirement::Build);

    let test_required = request
        .verification
        .contains(&VerificationRequirement::Test);

    let build_runs: Vec<_> = observation
        .runs
        .iter()
        .filter(|run| looks_like_build(&run.program, &run.args))
        .collect();

    let test_runs: Vec<_> = observation
        .runs
        .iter()
        .filter(|run| looks_like_test(&run.program, &run.args))
        .collect();

    let build_observed = !build_runs.is_empty();
    let test_observed = !test_runs.is_empty();

    let build_passed = build_runs.iter().any(|run| run.passed());
    let test_passed = test_runs.iter().any(|run| run.passed());

    let evidence_present = !observation.evidence.is_empty();
    let changed_files_present = !observation.changed_files.is_empty();

    let mut missing = Vec::new();

    if build_required && !build_observed {
        missing.push("required build observation missing".into());
    } else if build_required && !build_passed {
        missing.push("required build did not pass".into());
    }

    if test_required && !test_observed {
        missing.push("required test observation missing".into());
    } else if test_required && !test_passed {
        missing.push("required test did not pass".into());
    }

    if !evidence_present && !changed_files_present {
        missing.push("no machine evidence or changed files observed".into());
    }

    let mission_matches = request.assignment.mission_id == observation.mission_id.0;
    let agent_matches = request.agent.identity.id == observation.agent_id;

    if !mission_matches {
        missing.push("observation mission does not match execution request".into());
    }

    if !agent_matches {
        missing.push("observation agent does not match execution request".into());
    }

    VerificationReport {
        build_required,
        build_observed,
        build_passed,

        test_required,
        test_observed,
        test_passed,

        evidence_present,
        changed_files_present,

        verified: missing.is_empty(),
        missing,
    }
}

pub fn observation_to_telemetry(
    request: &BridgeExecutionRequest,
    observation: &ActualExecutionObservation,
) -> MissionTelemetry {
    let verification = verify_observation(request, observation);

    let build_result = if verification.build_observed {
        Some(if verification.build_passed {
            "PASS".into()
        } else {
            "FAIL".into()
        })
    } else {
        None
    };

    let test_result = if verification.test_observed {
        Some(if verification.test_passed {
            "PASS".into()
        } else {
            "FAIL".into()
        })
    } else {
        None
    };

    let mut evidence: Vec<String> = observation
        .evidence
        .iter()
        .map(|record| record.reference.clone())
        .collect();

    for run in &observation.runs {
        let command = format!("{} {}", run.program, run.args.join(" "));

        let status = if run.timed_out {
            "timeout".to_string()
        } else {
            match run.exit_code {
                Some(code) => format!("exit/{code}"),
                None => "exit/unknown".into(),
            }
        };

        evidence.push(format!("run://{}/{}", command.replace(' ', "_"), status));
    }

    let result = if observation.blocker.is_some() {
        TelemetryResult::Blocked
    } else if observation.scope_violations > 0 {
        TelemetryResult::Fail
    } else if verification.verified {
        TelemetryResult::Pass
    } else {
        TelemetryResult::Unknown
    };

    let blocker = if let Some(blocker) = &observation.blocker {
        Some(blocker.clone())
    } else if verification.verified {
        None
    } else {
        Some(verification.missing.join("; "))
    };

    MissionTelemetry {
        mission_id: observation.mission_id.clone(),
        worker: request.agent.identity.name.clone(),
        model: request.agent.brain.model.clone(),
        language: "compact-en".into(),
        result,
        duration_ms: observation.duration_ms,
        prompt_units: 0,
        retries: 0,
        changed_files: observation.changed_files.clone(),
        build_result,
        test_result,
        scope_violations: observation.scope_violations,
        human_interventions: observation.human_interventions,
        vram_mb: None,
        blocker,
        evidence,
    }
}

pub fn telemetry_is_reviewable(telemetry: &MissionTelemetry) -> bool {
    if telemetry.result != TelemetryResult::Pass {
        return true;
    }

    let has_change_evidence = !telemetry.changed_files.is_empty() || !telemetry.evidence.is_empty();

    let build_ok = telemetry
        .build_result
        .as_deref()
        .map(|value| value.eq_ignore_ascii_case("PASS"))
        .unwrap_or(true);

    let test_ok = telemetry
        .test_result
        .as_deref()
        .map(|value| value.eq_ignore_ascii_case("PASS"))
        .unwrap_or(true);

    has_change_evidence && build_ok && test_ok
}

#[cfg(test)]
mod wire_v1_receiver_contract_tests {
    use super::*;

    #[test]
    fn receives_locked_genesis_wire_v1_shape() {
        let payload = r#"
{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "execution-wire-v1",
  "mission_ids": [
    "mission-build-wire",
    "mission-test-wire"
  ],
  "runtime": [
    {
      "mission_id": "mission-build-wire",
      "capability": "RUN_BUILD",
      "run": {
        "program": "cargo",
        "args": ["build", "--workspace"],
        "cwd": "G:\\Vertex_Project\\Fixture",
        "exit_code": 0,
        "timed_out": false,
        "stdout_ref": "build ok",
        "stderr_ref": ""
      }
    },
    {
      "mission_id": "mission-test-wire",
      "capability": "RUN_TEST",
      "run": {
        "program": "cargo",
        "args": ["test", "--workspace"],
        "cwd": "G:\\Vertex_Project\\Fixture",
        "exit_code": 0,
        "timed_out": false,
        "stdout_ref": "tests ok",
        "stderr_ref": ""
      }
    }
  ],
  "vve": [],
  "changed_files": [],
  "human_gate": {
    "required": false,
    "reasons": []
  },
  "failed_missions": [],
  "denied_missions": []
}
"#;

        let wire =
            receive_genesis_observation_v1(payload).expect("locked Genesis Wire V1 must decode");

        assert_eq!(wire.schema, GENESIS_OBSERVATION_WIRE_V1);
        assert_eq!(wire.execution_id, "execution-wire-v1");

        assert_eq!(
            wire.mission_ids,
            vec![
                "mission-build-wire".to_string(),
                "mission-test-wire".to_string(),
            ]
        );

        assert_eq!(wire.runtime.len(), 2);

        let build = &wire.runtime[0];

        assert_eq!(build.mission_id, "mission-build-wire");
        assert_eq!(build.capability, "RUN_BUILD");
        assert_eq!(build.run.program, "cargo");
        assert_eq!(build.run.args, vec!["build", "--workspace"]);
        assert_eq!(build.run.cwd, r"G:\Vertex_Project\Fixture");
        assert_eq!(build.run.exit_code, Some(0));
        assert!(!build.run.timed_out);
        assert_eq!(build.run.stdout_ref.as_deref(), Some("build ok"));
        assert_eq!(build.run.stderr_ref.as_deref(), Some(""));

        let test = &wire.runtime[1];

        assert_eq!(test.mission_id, "mission-test-wire");
        assert_eq!(test.capability, "RUN_TEST");
        assert_eq!(test.run.program, "cargo");
        assert_eq!(test.run.args, vec!["test", "--workspace"]);
        assert_eq!(test.run.exit_code, Some(0));

        assert!(!wire.human_gate.required);
        assert!(wire.human_gate.reasons.is_empty());
        assert!(wire.failed_missions.is_empty());
        assert!(wire.denied_missions.is_empty());
    }

    #[test]
    fn rejects_unknown_genesis_wire_schema() {
        let payload = r#"
{
  "schema": "vertex.genesis.observation.v999",
  "execution_id": "execution-wire-v1",
  "mission_ids": [],
  "runtime": [],
  "vve": [],
  "changed_files": [],
  "human_gate": {
    "required": false,
    "reasons": []
  },
  "failed_missions": [],
  "denied_missions": []
}
"#;

        let error =
            receive_genesis_observation_v1(payload).expect_err("unknown schema must be rejected");

        assert!(error.contains("unsupported Genesis observation schema"));
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use vsa_agent_contracts::{
        BrainCartridge, CapabilityGrant, DockCapability, EvidenceRecord, HyperAgentIdentity,
        RunObservation, VesselBinding, VesselKind,
    };
    use vsa_ard::{ExecutionContract, MissionState, WorkUnit};
    use vsa_foundation::Id;
    use vsa_observatory::TelemetryResult;

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

    fn request(verification: Vec<VerificationRequirement>) -> BridgeExecutionRequest {
        build_execution_request(
            &sample_work_unit(),
            sample_agent(),
            sample_context(),
            verification,
        )
        .unwrap()
    }

    fn success_run(command: &str) -> RunObservation {
        RunObservation {
            program: "cargo".into(),
            args: vec![command.into()],
            cwd: "G:\\Vertex_Project\\Vertex_Studio_AI".into(),
            exit_code: Some(0),
            timed_out: false,
            stdout_ref: Some("evidence://stdout".into()),
            stderr_ref: None,
        }
    }

    fn sample_observation() -> ActualExecutionObservation {
        ActualExecutionObservation {
            mission_id: Id("mission-1".into()),
            agent_id: Id("agent-1".into()),
            changed_files: vec!["VVE/SOURCE/example.rs".into()],
            runs: vec![success_run("build"), success_run("test")],
            evidence: vec![EvidenceRecord {
                id: Id("evidence-1".into()),
                mission_id: Id("mission-1".into()),
                source: "vertex-runtime".into(),
                kind: "execution".into(),
                status: "PASS".into(),
                reference: "evidence://execution/1".into(),
                summary: "machine observed execution".into(),
            }],
            blocker: None,
            scope_violations: 0,
            human_interventions: 0,
            duration_ms: 1200,
        }
    }

    #[test]
    fn maps_work_unit_to_bridge_assignment() {
        let unit = sample_work_unit();
        let assignment = work_unit_to_assignment(&unit);

        assert_eq!(assignment.mission_id, "mission-1");
        assert_eq!(assignment.role, "Developer");
        assert_eq!(assignment.scope, vec!["VVE", "ARD"]);
        assert_eq!(assignment.forbidden, vec!["Bypass Human Gate"]);
    }

    #[test]
    fn multi_agent_dispatch_accepts_alpha_build_and_bravo_test() {
        let mut build_unit = sample_work_unit();
        build_unit.id = Id("mission-build".into());
        build_unit.title = "Build mission".into();

        let mut build_context = sample_context();
        build_context.context_id = Id("ctx-build".into());
        build_context.mission_id = Id("mission-build".into());

        let mut alpha = sample_agent();
        alpha.identity.id = Id("agent-alpha".into());
        alpha.identity.name = "Alpha".into();
        alpha.grant.agent_id = Id("agent-alpha".into());
        alpha.grant.allowed = vec![DockCapability::Build];

        let mut test_unit = sample_work_unit();
        test_unit.id = Id("mission-test".into());
        test_unit.title = "Test mission".into();

        let mut test_context = sample_context();
        test_context.context_id = Id("ctx-test".into());
        test_context.mission_id = Id("mission-test".into());

        let mut bravo = sample_agent();
        bravo.identity.id = Id("agent-bravo".into());
        bravo.identity.name = "Bravo".into();
        bravo.grant.agent_id = Id("agent-bravo".into());
        bravo.grant.allowed = vec![DockCapability::Test];

        let plan = build_multi_agent_dispatch_plan(vec![
            (
                build_unit,
                alpha,
                build_context,
                vec![VerificationRequirement::Build],
            ),
            (
                test_unit,
                bravo,
                test_context,
                vec![VerificationRequirement::Test],
            ),
        ])
        .expect("Alpha/Bravo dispatch must be accepted");

        assert_eq!(plan.dispatches.len(), 2);

        assert_eq!(
            plan.dispatches[0].request.assignment.mission_id,
            "mission-build"
        );
        assert_eq!(
            plan.dispatches[0].request.agent.identity.id,
            Id("agent-alpha".into())
        );

        assert_eq!(
            plan.dispatches[1].request.assignment.mission_id,
            "mission-test"
        );
        assert_eq!(
            plan.dispatches[1].request.agent.identity.id,
            Id("agent-bravo".into())
        );
    }

    #[test]
    fn multi_agent_dispatch_rejects_grant_swapping() {
        let unit = sample_work_unit();
        let context = sample_context();

        let mut alpha = sample_agent();
        alpha.identity.id = Id("agent-alpha".into());

        // Grant belongs to Bravo.
        alpha.grant.agent_id = Id("agent-bravo".into());

        let error = build_multi_agent_dispatch_plan(vec![(
            unit,
            alpha,
            context,
            vec![VerificationRequirement::Build],
        )])
        .expect_err("swapped grant must be rejected");

        assert!(error.contains("agent identity does not match capability grant"));
    }

    #[test]
    fn multi_agent_dispatch_rejects_vessel_swapping() {
        let unit = sample_work_unit();
        let context = sample_context();

        let mut alpha = sample_agent();
        alpha.identity.id = Id("agent-alpha".into());
        alpha.grant.agent_id = Id("agent-alpha".into());

        alpha.vessel.vessel_id = "mothership-alpha".into();
        alpha.grant.vessel_id = "mothership-bravo".into();

        let error = build_multi_agent_dispatch_plan(vec![(
            unit,
            alpha,
            context,
            vec![VerificationRequirement::Build],
        )])
        .expect_err("swapped vessel must be rejected");

        assert!(error.contains("vessel binding does not match capability grant"));
    }

    #[test]
    fn multi_agent_dispatch_rejects_capability_escalation() {
        let unit = sample_work_unit();
        let context = sample_context();

        let mut alpha = sample_agent();
        alpha.identity.id = Id("agent-alpha".into());
        alpha.grant.agent_id = Id("agent-alpha".into());

        alpha.grant.allowed = vec![DockCapability::Build];

        let error = build_multi_agent_dispatch_plan(vec![(
            unit,
            alpha,
            context,
            vec![VerificationRequirement::Test],
        )])
        .expect_err("Build-only agent must not claim Test verification");

        assert!(error.contains("TEST verification requires Test capability"));
    }

    #[test]
    fn multi_agent_dispatch_rejects_context_hijack() {
        let unit = sample_work_unit();

        let mut context = sample_context();
        context.mission_id = Id("mission-owned-by-other-agent".into());

        let mut alpha = sample_agent();
        alpha.identity.id = Id("agent-alpha".into());
        alpha.grant.agent_id = Id("agent-alpha".into());

        let error = build_multi_agent_dispatch_plan(vec![(
            unit,
            alpha,
            context,
            vec![VerificationRequirement::Build],
        )])
        .expect_err("foreign mission context must be rejected");

        assert!(error.contains("mission/context mismatch"));
    }

    #[test]
    fn multi_agent_dispatch_rejects_duplicate_agent_assignment() {
        let mut unit_a = sample_work_unit();
        unit_a.id = Id("mission-a".into());

        let mut context_a = sample_context();
        context_a.mission_id = Id("mission-a".into());

        let mut unit_b = sample_work_unit();
        unit_b.id = Id("mission-b".into());

        let mut context_b = sample_context();
        context_b.mission_id = Id("mission-b".into());

        let mut alpha_a = sample_agent();
        alpha_a.identity.id = Id("agent-alpha".into());
        alpha_a.grant.agent_id = Id("agent-alpha".into());

        let mut alpha_b = sample_agent();
        alpha_b.identity.id = Id("agent-alpha".into());
        alpha_b.grant.agent_id = Id("agent-alpha".into());

        let error = build_multi_agent_dispatch_plan(vec![
            (
                unit_a,
                alpha_a,
                context_a,
                vec![VerificationRequirement::Build],
            ),
            (
                unit_b,
                alpha_b,
                context_b,
                vec![VerificationRequirement::Build],
            ),
        ])
        .expect_err("same agent must not be dispatched twice");

        assert!(error.contains("duplicate agent"));
    }
    fn two_agent_dispatch_plan() -> MultiAgentDispatchPlan {
        let mut build_unit = sample_work_unit();
        build_unit.id = Id("mission-build".into());

        let mut build_context = sample_context();
        build_context.context_id = Id("ctx-build".into());
        build_context.mission_id = Id("mission-build".into());

        let mut alpha = sample_agent();
        alpha.identity.id = Id("agent-alpha".into());
        alpha.identity.name = "Alpha".into();
        alpha.grant.agent_id = Id("agent-alpha".into());
        alpha.grant.allowed = vec![DockCapability::Build];

        let mut test_unit = sample_work_unit();
        test_unit.id = Id("mission-test".into());

        let mut test_context = sample_context();
        test_context.context_id = Id("ctx-test".into());
        test_context.mission_id = Id("mission-test".into());

        let mut bravo = sample_agent();
        bravo.identity.id = Id("agent-bravo".into());
        bravo.identity.name = "Bravo".into();
        bravo.grant.agent_id = Id("agent-bravo".into());
        bravo.grant.allowed = vec![DockCapability::Test];

        build_multi_agent_dispatch_plan(vec![
            (
                build_unit,
                alpha,
                build_context,
                vec![VerificationRequirement::Build],
            ),
            (
                test_unit,
                bravo,
                test_context,
                vec![VerificationRequirement::Test],
            ),
        ])
        .unwrap()
    }

    fn returned_observation(
        mission_id: &str,
        capability: &str,
        command: &str,
    ) -> GenesisObservation {
        GenesisObservation {
            mission_id: mission_id.into(),
            actor: "genesis".into(),
            capability: capability.into(),
            state: GenesisMissionState::Completed,
            runs: vec![GenesisRunObservation {
                program: "cargo".into(),
                args: vec![command.into()],
                cwd: "G:\\Vertex_Project\\Vertex_Studio_AI".into(),
                exit_code: Some(0),
                timed_out: false,
                stdout_ref: Some(format!("evidence://stdout/{mission_id}")),
                stderr_ref: None,
            }],
            changeset_id: None,
            changed_files: vec![],
            audit_ref: Some(format!("genesis://return/{mission_id}")),
            blocker: None,
            duration_ms: 1,
        }
    }

    #[test]
    fn return_to_mothership_accepts_alpha_and_bravo() {
        let plan = two_agent_dispatch_plan();

        let recovery = recover_multi_agent_dispatch(
            &plan,
            vec![
                AgentMissionReturn {
                    mission_id: "mission-build".into(),
                    agent_id: Id("agent-alpha".into()),
                    observation: returned_observation("mission-build", "RUN_BUILD", "build"),
                },
                AgentMissionReturn {
                    mission_id: "mission-test".into(),
                    agent_id: Id("agent-bravo".into()),
                    observation: returned_observation("mission-test", "RUN_TEST", "test"),
                },
            ],
        )
        .expect("Alpha and Bravo must recover");

        assert_eq!(recovery.recovered.len(), 2);

        let alpha = recovery
            .recovered
            .iter()
            .find(|item| item.request.assignment.mission_id == "mission-build")
            .unwrap();

        let bravo = recovery
            .recovered
            .iter()
            .find(|item| item.request.assignment.mission_id == "mission-test")
            .unwrap();

        assert_eq!(alpha.request.agent.identity.id, Id("agent-alpha".into()));
        assert_eq!(alpha.observation.mission_id, "mission-build");

        assert_eq!(bravo.request.agent.identity.id, Id("agent-bravo".into()));
        assert_eq!(bravo.observation.mission_id, "mission-test");
    }

    #[test]
    fn return_to_mothership_rejects_unknown_mission() {
        let plan = two_agent_dispatch_plan();

        let error = recover_multi_agent_dispatch(
            &plan,
            vec![AgentMissionReturn {
                mission_id: "mission-unknown".into(),
                agent_id: Id("agent-alpha".into()),
                observation: returned_observation("mission-unknown", "RUN_BUILD", "build"),
            }],
        )
        .expect_err("unknown mission must not dock");

        assert!(error.contains("unknown dispatched mission"));
    }

    #[test]
    fn return_to_mothership_rejects_agent_spoofing() {
        let plan = two_agent_dispatch_plan();

        let error = recover_multi_agent_dispatch(
            &plan,
            vec![
                AgentMissionReturn {
                    mission_id: "mission-build".into(),

                    // Bravo attempts to return Alpha's mission.
                    agent_id: Id("agent-bravo".into()),

                    observation: returned_observation("mission-build", "RUN_BUILD", "build"),
                },
                AgentMissionReturn {
                    mission_id: "mission-test".into(),
                    agent_id: Id("agent-bravo".into()),
                    observation: returned_observation("mission-test", "RUN_TEST", "test"),
                },
            ],
        )
        .expect_err("agent spoofing must not dock");

        assert!(error.contains("return agent does not match dispatched agent"));
    }

    #[test]
    fn return_to_mothership_rejects_duplicate_return() {
        let plan = two_agent_dispatch_plan();

        let error = recover_multi_agent_dispatch(
            &plan,
            vec![
                AgentMissionReturn {
                    mission_id: "mission-build".into(),
                    agent_id: Id("agent-alpha".into()),
                    observation: returned_observation("mission-build", "RUN_BUILD", "build"),
                },
                AgentMissionReturn {
                    mission_id: "mission-build".into(),
                    agent_id: Id("agent-alpha".into()),
                    observation: returned_observation("mission-build", "RUN_BUILD", "build"),
                },
            ],
        )
        .expect_err("duplicate return must not dock");

        assert!(error.contains("duplicate mission return"));
    }

    #[test]
    fn return_to_mothership_rejects_missing_return() {
        let plan = two_agent_dispatch_plan();

        let error = recover_multi_agent_dispatch(
            &plan,
            vec![AgentMissionReturn {
                mission_id: "mission-build".into(),
                agent_id: Id("agent-alpha".into()),
                observation: returned_observation("mission-build", "RUN_BUILD", "build"),
            }],
        )
        .expect_err("all dispatched missions must return");

        assert!(error.contains("not all dispatched missions returned"));
        assert!(error.contains("mission-test"));
    }

    #[test]
    fn return_to_mothership_rejects_observation_mission_swap() {
        let plan = two_agent_dispatch_plan();

        let error = recover_multi_agent_dispatch(
            &plan,
            vec![
                AgentMissionReturn {
                    mission_id: "mission-build".into(),
                    agent_id: Id("agent-alpha".into()),

                    // Envelope says Build, payload says Test.
                    observation: returned_observation("mission-test", "RUN_BUILD", "build"),
                },
                AgentMissionReturn {
                    mission_id: "mission-test".into(),
                    agent_id: Id("agent-bravo".into()),
                    observation: returned_observation("mission-test", "RUN_TEST", "test"),
                },
            ],
        )
        .expect_err("swapped observation must not dock");

        assert!(error.contains("return/observation mission mismatch"));
    }
    #[test]
    fn mothership_full_cycle_alpha_and_bravo_reach_ard_pass() {
        let plan = two_agent_dispatch_plan();

        let recovery = recover_multi_agent_dispatch(
            &plan,
            vec![
                AgentMissionReturn {
                    mission_id: "mission-build".into(),
                    agent_id: Id("agent-alpha".into()),
                    observation: returned_observation("mission-build", "RUN_BUILD", "build"),
                },
                AgentMissionReturn {
                    mission_id: "mission-test".into(),
                    agent_id: Id("agent-bravo".into()),
                    observation: returned_observation("mission-test", "RUN_TEST", "test"),
                },
            ],
        )
        .expect("Alpha and Bravo must recover");

        let cycle = complete_mothership_recovery(&recovery).expect("full cycle must complete");

        assert_eq!(cycle.outcomes.len(), 2);

        let alpha = cycle
            .outcomes
            .iter()
            .find(|item| item.mission_id == "mission-build")
            .unwrap();

        let bravo = cycle
            .outcomes
            .iter()
            .find(|item| item.mission_id == "mission-test")
            .unwrap();

        assert_eq!(alpha.agent_id, Id("agent-alpha".into()));
        assert_eq!(alpha.telemetry.result, TelemetryResult::Pass);
        assert_eq!(alpha.footer.result, MissionState::Pass);

        assert_eq!(bravo.agent_id, Id("agent-bravo".into()));
        assert_eq!(bravo.telemetry.result, TelemetryResult::Pass);
        assert_eq!(bravo.footer.result, MissionState::Pass);
    }

    #[test]
    fn mothership_full_cycle_bravo_failure_does_not_poison_alpha() {
        let plan = two_agent_dispatch_plan();

        let alpha_observation = returned_observation("mission-build", "RUN_BUILD", "build");

        let mut bravo_observation = returned_observation("mission-test", "RUN_TEST", "test");

        bravo_observation.state = GenesisMissionState::Failed;

        bravo_observation.runs[0].exit_code = Some(1);

        bravo_observation.runs[0].stderr_ref = Some("evidence://stderr/mission-test".into());

        bravo_observation.blocker = Some("test execution failed".into());

        let recovery = recover_multi_agent_dispatch(
            &plan,
            vec![
                AgentMissionReturn {
                    mission_id: "mission-build".into(),
                    agent_id: Id("agent-alpha".into()),
                    observation: alpha_observation,
                },
                AgentMissionReturn {
                    mission_id: "mission-test".into(),
                    agent_id: Id("agent-bravo".into()),
                    observation: bravo_observation,
                },
            ],
        )
        .expect("identity-correct returns must recover");

        let cycle = complete_mothership_recovery(&recovery).expect("full cycle must complete");

        let alpha = cycle
            .outcomes
            .iter()
            .find(|item| item.mission_id == "mission-build")
            .unwrap();

        let bravo = cycle
            .outcomes
            .iter()
            .find(|item| item.mission_id == "mission-test")
            .unwrap();

        assert_eq!(alpha.agent_id, Id("agent-alpha".into()));
        assert_eq!(alpha.telemetry.result, TelemetryResult::Pass);
        assert_eq!(alpha.footer.result, MissionState::Pass);
        assert!(alpha.footer.current_blocker.is_none());

        assert_eq!(bravo.agent_id, Id("agent-bravo".into()));

        assert_ne!(
            bravo.telemetry.result,
            TelemetryResult::Pass,
            "Bravo failure must never become PASS telemetry"
        );

        assert_ne!(
            bravo.footer.result,
            MissionState::Pass,
            "Bravo failure must never become ARD PASS"
        );

        assert!(bravo.footer.current_blocker.is_some());

        // The critical isolation guarantee:
        // Bravo's failure cannot contaminate Alpha.
        assert_eq!(alpha.telemetry.result, TelemetryResult::Pass);
        assert_eq!(alpha.footer.result, MissionState::Pass);
    }

    #[test]
    fn mothership_full_cycle_preserves_agent_mission_binding() {
        let plan = two_agent_dispatch_plan();

        let recovery = recover_multi_agent_dispatch(
            &plan,
            vec![
                AgentMissionReturn {
                    mission_id: "mission-build".into(),
                    agent_id: Id("agent-alpha".into()),
                    observation: returned_observation("mission-build", "RUN_BUILD", "build"),
                },
                AgentMissionReturn {
                    mission_id: "mission-test".into(),
                    agent_id: Id("agent-bravo".into()),
                    observation: returned_observation("mission-test", "RUN_TEST", "test"),
                },
            ],
        )
        .unwrap();

        let cycle = complete_mothership_recovery(&recovery).unwrap();

        let alpha = cycle
            .outcomes
            .iter()
            .find(|item| item.mission_id == "mission-build")
            .unwrap();

        let bravo = cycle
            .outcomes
            .iter()
            .find(|item| item.mission_id == "mission-test")
            .unwrap();

        assert_eq!(alpha.agent_id, Id("agent-alpha".into()));

        assert_eq!(bravo.agent_id, Id("agent-bravo".into()));

        assert_ne!(alpha.agent_id, bravo.agent_id);
        assert_ne!(alpha.mission_id, bravo.mission_id);
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

    #[test]
    fn fleet_orchestration_assigns_build_test_and_vve_by_capability() {
        let missions = vec![
            fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            ),
            fleet_mission(
                "mission-test",
                DockCapability::Test,
                vec![VerificationRequirement::Test],
            ),
            fleet_mission("mission-vve", DockCapability::VveValidate, vec![]),
        ];

        // Deliberately provide Agents out of ID order.
        let agents = vec![
            fleet_agent("agent-charlie", vec![DockCapability::VveValidate]),
            fleet_agent("agent-bravo", vec![DockCapability::Test]),
            fleet_agent("agent-alpha", vec![DockCapability::Build]),
        ];

        let plan = build_fleet_dispatch_plan(missions, agents).expect("Fleet must dispatch");

        assert_eq!(plan.dispatches.len(), 3);

        assert_eq!(
            plan.dispatches[0].request.assignment.mission_id,
            "mission-build"
        );
        assert_eq!(
            plan.dispatches[0].request.agent.identity.id,
            Id("agent-alpha".into())
        );

        assert_eq!(
            plan.dispatches[1].request.assignment.mission_id,
            "mission-test"
        );
        assert_eq!(
            plan.dispatches[1].request.agent.identity.id,
            Id("agent-bravo".into())
        );

        assert_eq!(
            plan.dispatches[2].request.assignment.mission_id,
            "mission-vve"
        );
        assert_eq!(
            plan.dispatches[2].request.agent.identity.id,
            Id("agent-charlie".into())
        );
    }

    #[test]
    fn fleet_orchestration_selects_lowest_agent_id_deterministically() {
        let missions = vec![fleet_mission(
            "mission-build",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        )];

        // Both can BUILD. Input order must not decide.
        let agents = vec![
            fleet_agent("agent-zulu", vec![DockCapability::Build]),
            fleet_agent("agent-alpha", vec![DockCapability::Build]),
        ];

        let plan = build_fleet_dispatch_plan(missions, agents).expect("Fleet must dispatch");

        assert_eq!(
            plan.dispatches[0].request.agent.identity.id,
            Id("agent-alpha".into())
        );
    }

    #[test]
    fn fleet_orchestration_rejects_missing_capability() {
        let missions = vec![fleet_mission(
            "mission-test",
            DockCapability::Test,
            vec![VerificationRequirement::Test],
        )];

        let agents = vec![fleet_agent("agent-alpha", vec![DockCapability::Build])];

        let error = build_fleet_dispatch_plan(missions, agents)
            .expect_err("missing capability must fail closed");

        assert!(error.contains("no available fleet agent has required capability"));
        assert!(error.contains("mission-test"));
    }

    #[test]
    fn fleet_orchestration_does_not_reuse_agent_in_same_dispatch() {
        let missions = vec![
            fleet_mission(
                "mission-build-a",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            ),
            fleet_mission(
                "mission-build-b",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            ),
        ];

        let agents = vec![fleet_agent("agent-alpha", vec![DockCapability::Build])];

        let error = build_fleet_dispatch_plan(missions, agents)
            .expect_err("one Agent must not receive two Fleet missions");

        assert!(error.contains("no available fleet agent has required capability"));
        assert!(error.contains("mission-build-b"));
    }

    #[test]
    fn fleet_orchestration_rejects_duplicate_mission() {
        let missions = vec![
            fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            ),
            fleet_mission(
                "mission-build",
                DockCapability::Test,
                vec![VerificationRequirement::Test],
            ),
        ];

        let agents = vec![
            fleet_agent("agent-alpha", vec![DockCapability::Build]),
            fleet_agent("agent-bravo", vec![DockCapability::Test]),
        ];

        let error = build_fleet_dispatch_plan(missions, agents)
            .expect_err("duplicate Fleet mission must be rejected");

        assert!(error.contains("duplicate mission in fleet dispatch"));
    }

    #[test]
    fn fleet_orchestration_preserves_existing_context_boundary() {
        let mut mission = fleet_mission(
            "mission-build",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        // Scheduler may select an Agent, but the existing
        // Bridge boundary must still reject a hijacked context.
        mission.context.mission_id = Id("mission-foreign".into());

        let agents = vec![fleet_agent("agent-alpha", vec![DockCapability::Build])];

        let error = build_fleet_dispatch_plan(vec![mission], agents)
            .expect_err("Fleet scheduler must not bypass Bridge validation");

        assert!(error.contains("mission/context mismatch"));
    }
    #[test]
    fn fleet_phase2_dispatches_only_root_ready_wave() {
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

        let agents = vec![
            fleet_agent("agent-alpha", vec![DockCapability::Build]),
            fleet_agent("agent-bravo", vec![DockCapability::Test]),
            fleet_agent("agent-charlie", vec![DockCapability::VveValidate]),
        ];

        let wave = build_dependency_aware_fleet_wave(vec![build, test, vve], agents)
            .expect("Wave 1 must schedule");

        assert_eq!(wave.ready_mission_ids, vec!["mission-build".to_string()]);

        assert_eq!(
            wave.waiting_mission_ids,
            vec!["mission-test".to_string(), "mission-vve".to_string(),]
        );

        assert!(wave.blocked_mission_ids.is_empty());

        let dispatch = wave.dispatch.expect("Build must dispatch");

        assert_eq!(dispatch.dispatches.len(), 1);

        assert_eq!(
            dispatch.dispatches[0].request.assignment.mission_id,
            "mission-build"
        );

        assert_eq!(
            dispatch.dispatches[0].request.agent.identity.id,
            Id("agent-alpha".into())
        );
    }

    #[test]
    fn fleet_phase2_pass_unlocks_next_wave() {
        let mut build = fleet_mission(
            "mission-build",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        build.unit.state = MissionState::Pass;

        let mut test = fleet_mission(
            "mission-test",
            DockCapability::Test,
            vec![VerificationRequirement::Test],
        );

        test.unit.depends_on = vec![Id("mission-build".into())];

        let agents = vec![fleet_agent("agent-bravo", vec![DockCapability::Test])];

        let wave = build_dependency_aware_fleet_wave(vec![build, test], agents)
            .expect("Test wave must unlock");

        assert_eq!(wave.ready_mission_ids, vec!["mission-test".to_string()]);

        assert!(wave.waiting_mission_ids.is_empty());
        assert!(wave.blocked_mission_ids.is_empty());

        let dispatch = wave.dispatch.expect("Test must dispatch");

        assert_eq!(dispatch.dispatches.len(), 1);

        assert_eq!(
            dispatch.dispatches[0].request.assignment.mission_id,
            "mission-test"
        );
    }

    #[test]
    fn fleet_phase2_dispatches_parallel_ready_missions_in_same_wave() {
        let build_a = fleet_mission(
            "mission-build-a",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        let build_b = fleet_mission(
            "mission-build-b",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        let agents = vec![
            fleet_agent("agent-bravo", vec![DockCapability::Build]),
            fleet_agent("agent-alpha", vec![DockCapability::Build]),
        ];

        let wave = build_dependency_aware_fleet_wave(vec![build_b, build_a], agents)
            .expect("parallel roots must dispatch");

        assert_eq!(
            wave.ready_mission_ids,
            vec!["mission-build-a".to_string(), "mission-build-b".to_string(),]
        );

        let dispatch = wave.dispatch.expect("Ready wave must dispatch");

        assert_eq!(dispatch.dispatches.len(), 2);

        assert_eq!(
            dispatch.dispatches[0].request.assignment.mission_id,
            "mission-build-a"
        );

        assert_eq!(
            dispatch.dispatches[0].request.agent.identity.id,
            Id("agent-alpha".into())
        );

        assert_eq!(
            dispatch.dispatches[1].request.assignment.mission_id,
            "mission-build-b"
        );

        assert_eq!(
            dispatch.dispatches[1].request.agent.identity.id,
            Id("agent-bravo".into())
        );
    }

    #[test]
    fn fleet_phase2_failed_dependency_blocks_downstream_transitively() {
        let mut build = fleet_mission(
            "mission-build",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        build.unit.state = MissionState::Fail;

        let mut test = fleet_mission(
            "mission-test",
            DockCapability::Test,
            vec![VerificationRequirement::Test],
        );

        test.unit.depends_on = vec![Id("mission-build".into())];

        let mut vve = fleet_mission("mission-vve", DockCapability::VveValidate, vec![]);

        vve.unit.depends_on = vec![Id("mission-test".into())];

        let wave = build_dependency_aware_fleet_wave(vec![build, test, vve], vec![])
            .expect("failed dependency must produce blocked wave, not dispatch");

        assert!(wave.ready_mission_ids.is_empty());
        assert!(wave.waiting_mission_ids.is_empty());

        assert_eq!(
            wave.blocked_mission_ids,
            vec!["mission-test".to_string(), "mission-vve".to_string(),]
        );

        assert!(wave.dispatch.is_none());
    }

    #[test]
    fn fleet_phase2_rejects_missing_dependency() {
        let mut test = fleet_mission(
            "mission-test",
            DockCapability::Test,
            vec![VerificationRequirement::Test],
        );

        test.unit.depends_on = vec![Id("mission-does-not-exist".into())];

        let error = build_dependency_aware_fleet_wave(vec![test], vec![])
            .expect_err("missing dependency must fail closed");

        assert!(error.contains("references missing dependency"));

        assert!(error.contains("mission-does-not-exist"));
    }

    #[test]
    fn fleet_phase2_rejects_dependency_cycle() {
        let mut alpha = fleet_mission(
            "mission-alpha",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        alpha.unit.depends_on = vec![Id("mission-bravo".into())];

        let mut bravo = fleet_mission(
            "mission-bravo",
            DockCapability::Test,
            vec![VerificationRequirement::Test],
        );

        bravo.unit.depends_on = vec![Id("mission-alpha".into())];

        let error = build_dependency_aware_fleet_wave(vec![alpha, bravo], vec![])
            .expect_err("dependency cycle must fail closed");

        assert!(error.contains("cycle detected in fleet mission dependency graph"));
    }
    fn single_mission_cycle(
        plan: &MultiAgentDispatchPlan,
        mission_id: &str,
        agent_id: &str,
        observation: GenesisObservation,
    ) -> MothershipFullCycle {
        let recovery = recover_multi_agent_dispatch(
            plan,
            vec![AgentMissionReturn {
                mission_id: mission_id.into(),
                agent_id: Id(agent_id.into()),
                observation,
            }],
        )
        .expect("single mission must recover");

        complete_mothership_recovery(&recovery).expect("single mission cycle must complete")
    }

    #[test]
    fn fleet_phase4_build_failure_stops_session() {
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

        let session = start_fleet_controller_session(
            vec![build, test, vve],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("controller session must start");

        let dispatch = session
            .current_wave
            .dispatch
            .clone()
            .expect("BUILD must dispatch");

        let mut failed = returned_observation("mission-build", "RUN_BUILD", "build");

        failed.state = GenesisMissionState::Failed;
        failed.runs[0].exit_code = Some(1);
        failed.runs[0].stderr_ref = Some("evidence://stderr/build".into());
        failed.blocker = Some("build failed".into());

        let cycle = single_mission_cycle(&dispatch, "mission-build", "agent-alpha", failed);

        let session = advance_fleet_controller_session(session, &dispatch, &cycle, vec![])
            .expect("failed BUILD must safely stop session");

        assert_eq!(session.status, FleetControllerSessionStatus::Stopped);
        assert_eq!(session.completed_waves, 1);

        assert!(session.current_wave.dispatch.is_none());
        assert!(session.current_wave.ready_mission_ids.is_empty());

        assert_eq!(
            session.current_wave.blocked_mission_ids,
            vec!["mission-test".to_string(), "mission-vve".to_string(),]
        );
    }

    #[test]
    fn fleet_phase4_rejects_advance_after_completion() {
        let mission = fleet_mission(
            "mission-build",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        let session = start_fleet_controller_session(
            vec![mission],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .unwrap();

        let dispatch = session.current_wave.dispatch.clone().unwrap();

        let cycle = single_mission_cycle(
            &dispatch,
            "mission-build",
            "agent-alpha",
            returned_observation("mission-build", "RUN_BUILD", "build"),
        );

        let completed = advance_fleet_controller_session(session, &dispatch, &cycle, vec![])
            .expect("single mission must complete");

        assert_eq!(completed.status, FleetControllerSessionStatus::Completed);

        let error = advance_fleet_controller_session(completed, &dispatch, &cycle, vec![])
            .expect_err("terminal session must reject another advance");

        assert!(error.contains("cannot advance a terminal fleet controller session"));
    }

    #[test]
    fn fleet_phase4_rejects_wrong_wave_dispatch() {
        let mission = fleet_mission(
            "mission-build",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        let session = start_fleet_controller_session(
            vec![mission],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .unwrap();

        let expected_dispatch = session.current_wave.dispatch.clone().unwrap();

        let wrong_mission = fleet_mission(
            "mission-other",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        let wrong_wave = build_dependency_aware_fleet_wave(
            vec![wrong_mission],
            vec![fleet_agent("agent-bravo", vec![DockCapability::Build])],
        )
        .unwrap();

        let wrong_dispatch = wrong_wave.dispatch.unwrap();

        let cycle = single_mission_cycle(
            &expected_dispatch,
            "mission-build",
            "agent-alpha",
            returned_observation("mission-build", "RUN_BUILD", "build"),
        );

        let error = advance_fleet_controller_session(session, &wrong_dispatch, &cycle, vec![])
            .expect_err("foreign wave dispatch must fail closed");

        assert!(error.contains("completed dispatch mission is not in current controller wave"));
    }

    #[test]
    fn fleet_phase4_rejects_dispatch_agent_substitution() {
        let mission = fleet_mission(
            "mission-build",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        let session = start_fleet_controller_session(
            vec![mission],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .unwrap();

        let expected_dispatch = session.current_wave.dispatch.clone().unwrap();

        let substituted_wave = build_dependency_aware_fleet_wave(
            vec![fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            )],
            vec![fleet_agent("agent-bravo", vec![DockCapability::Build])],
        )
        .unwrap();

        let substituted_dispatch = substituted_wave.dispatch.unwrap();

        let cycle = single_mission_cycle(
            &expected_dispatch,
            "mission-build",
            "agent-alpha",
            returned_observation("mission-build", "RUN_BUILD", "build"),
        );

        let error =
            advance_fleet_controller_session(session, &substituted_dispatch, &cycle, vec![])
                .expect_err("Agent substitution must fail closed");

        assert!(error.contains("completed dispatch agent does not match current controller wave"));
    }

    #[test]
    fn fleet_phase4_rejects_replayed_previous_wave() {
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

        let session = start_fleet_controller_session(
            vec![build, test],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .unwrap();

        let build_dispatch = session.current_wave.dispatch.clone().unwrap();

        let build_cycle = single_mission_cycle(
            &build_dispatch,
            "mission-build",
            "agent-alpha",
            returned_observation("mission-build", "RUN_BUILD", "build"),
        );

        let session = advance_fleet_controller_session(
            session,
            &build_dispatch,
            &build_cycle,
            vec![fleet_agent("agent-bravo", vec![DockCapability::Test])],
        )
        .expect("BUILD must advance session to TEST");

        assert_eq!(
            session.current_wave.ready_mission_ids,
            vec!["mission-test".to_string()]
        );

        let error =
            advance_fleet_controller_session(session, &build_dispatch, &build_cycle, vec![])
                .expect_err("previous BUILD wave must not be replayable");

        assert!(error.contains("completed dispatch mission is not in current controller wave"));
    }
    #[test]
    fn fleet_phase4_test_failure_stops_session() {
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

        // Wave 1: BUILD
        let session = start_fleet_controller_session(
            vec![build, test, vve],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("controller session must start");

        let build_dispatch = session
            .current_wave
            .dispatch
            .clone()
            .expect("BUILD must dispatch");

        let build_cycle = single_mission_cycle(
            &build_dispatch,
            "mission-build",
            "agent-alpha",
            returned_observation("mission-build", "RUN_BUILD", "build"),
        );

        // Wave 2: TEST
        let session = advance_fleet_controller_session(
            session,
            &build_dispatch,
            &build_cycle,
            vec![fleet_agent("agent-bravo", vec![DockCapability::Test])],
        )
        .expect("BUILD must advance controller to TEST");

        assert_eq!(session.status, FleetControllerSessionStatus::Active);

        let test_dispatch = session
            .current_wave
            .dispatch
            .clone()
            .expect("TEST must dispatch");

        let mut failed = returned_observation("mission-test", "RUN_TEST", "test");

        failed.state = GenesisMissionState::Failed;
        failed.runs[0].exit_code = Some(1);
        failed.runs[0].stderr_ref = Some("evidence://stderr/test".into());
        failed.blocker = Some("test failed".into());

        let test_cycle =
            single_mission_cycle(&test_dispatch, "mission-test", "agent-bravo", failed);

        let session =
            advance_fleet_controller_session(session, &test_dispatch, &test_cycle, vec![])
                .expect("failed TEST must safely stop controller session");

        assert_eq!(session.status, FleetControllerSessionStatus::Stopped);

        assert_eq!(session.completed_waves, 2);

        assert!(session.current_wave.dispatch.is_none());
        assert!(session.current_wave.ready_mission_ids.is_empty());

        assert_eq!(
            session.current_wave.blocked_mission_ids,
            vec!["mission-vve".to_string()]
        );

        let test_state = session
            .missions
            .iter()
            .find(|mission| mission.unit.id == Id("mission-test".into()))
            .expect("TEST mission must remain in controller state")
            .unit
            .state;

        assert_eq!(test_state, MissionState::Blocked);
    }

    #[test]
    fn fleet_phase4_vve_failure_never_completes_session() {
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

        // Wave 1: BUILD
        let session = start_fleet_controller_session(
            vec![build, test, vve],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("controller session must start");

        let build_dispatch = session
            .current_wave
            .dispatch
            .clone()
            .expect("BUILD must dispatch");

        let build_cycle = single_mission_cycle(
            &build_dispatch,
            "mission-build",
            "agent-alpha",
            returned_observation("mission-build", "RUN_BUILD", "build"),
        );

        // Wave 2: TEST
        let session = advance_fleet_controller_session(
            session,
            &build_dispatch,
            &build_cycle,
            vec![fleet_agent("agent-bravo", vec![DockCapability::Test])],
        )
        .expect("BUILD must advance controller to TEST");

        let test_dispatch = session
            .current_wave
            .dispatch
            .clone()
            .expect("TEST must dispatch");

        let test_cycle = single_mission_cycle(
            &test_dispatch,
            "mission-test",
            "agent-bravo",
            returned_observation("mission-test", "RUN_TEST", "test"),
        );

        // Wave 3: VVE
        let session = advance_fleet_controller_session(
            session,
            &test_dispatch,
            &test_cycle,
            vec![fleet_agent(
                "agent-charlie",
                vec![DockCapability::VveValidate],
            )],
        )
        .expect("TEST must advance controller to VVE");

        assert_eq!(session.status, FleetControllerSessionStatus::Active);

        let vve_dispatch = session
            .current_wave
            .dispatch
            .clone()
            .expect("VVE must dispatch");

        let mut failed = returned_observation("mission-vve", "RUN_VVE", "vve");

        failed.state = GenesisMissionState::Failed;
        failed.runs[0].exit_code = Some(1);
        failed.runs[0].stderr_ref = Some("evidence://stderr/vve".into());
        failed.blocker = Some("VVE validation failed".into());

        let vve_cycle = single_mission_cycle(&vve_dispatch, "mission-vve", "agent-charlie", failed);

        let session = advance_fleet_controller_session(session, &vve_dispatch, &vve_cycle, vec![])
            .expect("failed VVE must safely stop controller session");

        // Critical invariant:
        // VVE failure must NEVER be promoted to Completed.
        assert_eq!(session.status, FleetControllerSessionStatus::Stopped);

        assert_ne!(session.status, FleetControllerSessionStatus::Completed);

        assert_eq!(session.completed_waves, 3);

        assert!(session.current_wave.dispatch.is_none());
        assert!(session.current_wave.ready_mission_ids.is_empty());

        let vve_state = session
            .missions
            .iter()
            .find(|mission| mission.unit.id == Id("mission-vve".into()))
            .expect("VVE mission must remain in controller state")
            .unit
            .state;

        assert_eq!(vve_state, MissionState::Blocked);
    }
    #[test]
    fn fleet_phase4_1_accepts_current_execution_proof() {
        let mission = fleet_mission(
            "mission-build",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        let plan = build_fleet_dispatch_plan(
            vec![mission],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("current dispatch must build");

        let execution_id = plan.dispatches[0].execution_id.clone();

        let mut observation = returned_observation("mission-build", "RUN_BUILD", "build");

        observation.audit_ref = Some(format!("genesis://execution/{execution_id}"));

        let recovery = recover_multi_agent_dispatch(
            &plan,
            vec![AgentMissionReturn {
                mission_id: "mission-build".into(),
                agent_id: Id("agent-alpha".into()),
                observation,
            }],
        )
        .expect("matching execution proof must dock successfully");

        assert_eq!(recovery.recovered.len(), 1);
    }

    #[test]
    fn fleet_phase4_1_rejects_stale_execution_proof() {
        let old_plan = build_fleet_dispatch_plan(
            vec![fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            )],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("old dispatch must build");

        let current_plan = build_fleet_dispatch_plan(
            vec![fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            )],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("current dispatch must build");

        let old_execution = old_plan.dispatches[0].execution_id.clone();

        let current_execution = current_plan.dispatches[0].execution_id.clone();

        assert_ne!(
            old_execution, current_execution,
            "separate dispatch attempts must receive unique execution IDs"
        );

        let mut replayed = returned_observation("mission-build", "RUN_BUILD", "build");

        replayed.audit_ref = Some(format!("genesis://execution/{old_execution}"));

        let error = recover_multi_agent_dispatch(
            &current_plan,
            vec![AgentMissionReturn {
                mission_id: "mission-build".into(),
                agent_id: Id("agent-alpha".into()),
                observation: replayed,
            }],
        )
        .expect_err("stale execution proof must fail closed");

        assert!(
            error.contains("execution proof mismatch"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn fleet_phase4_1_controller_rejects_same_mission_agent_old_dispatch() {
        let old_plan = build_fleet_dispatch_plan(
            vec![fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            )],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("old dispatch must build");

        let current_plan = build_fleet_dispatch_plan(
            vec![fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            )],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("current dispatch must build");

        // Mission is identical.
        assert_eq!(
            old_plan.dispatches[0].request.assignment.mission_id,
            current_plan.dispatches[0].request.assignment.mission_id
        );

        // Agent is identical.
        assert_eq!(
            old_plan.dispatches[0].request.agent.identity.id,
            current_plan.dispatches[0].request.agent.identity.id
        );

        // Execution generation is NOT identical.
        assert_ne!(
            old_plan.dispatches[0].execution_id,
            current_plan.dispatches[0].execution_id
        );

        let error = validate_session_dispatch(&current_plan, &old_plan)
            .expect_err("old execution must not impersonate current dispatch");

        assert!(
            error.contains("completed dispatch execution does not match current controller wave"),
            "unexpected error: {error}"
        );
    }
    #[test]
    fn fleet_phase4_2_lineage_backbone_is_present() {
        let session = start_fleet_controller_session(
            vec![fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            )],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("controller session must start");

        assert!(
            session.session_id.starts_with("vsa-session-"),
            "unexpected session id: {}",
            session.session_id
        );

        assert!(
            session.current_wave.wave_id.starts_with("vsa-wave-"),
            "unexpected wave id: {}",
            session.current_wave.wave_id
        );

        let dispatch = session
            .current_wave
            .dispatch
            .as_ref()
            .expect("BUILD must dispatch");

        assert!(
            dispatch.dispatch_id.starts_with("vsa-dispatch-"),
            "unexpected dispatch id: {}",
            dispatch.dispatch_id
        );

        assert!(dispatch.dispatches[0].execution_id.starts_with("vsa-exec-"));
    }

    #[test]
    fn fleet_phase4_2_separate_sessions_have_separate_lineage() {
        let make_session = || {
            start_fleet_controller_session(
                vec![fleet_mission(
                    "mission-build",
                    DockCapability::Build,
                    vec![VerificationRequirement::Build],
                )],
                vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
            )
            .expect("controller session must start")
        };

        let first = make_session();
        let second = make_session();

        assert_ne!(first.session_id, second.session_id);
        assert_ne!(first.current_wave.wave_id, second.current_wave.wave_id);

        assert_ne!(
            first.current_wave.dispatch.as_ref().unwrap().dispatch_id,
            second.current_wave.dispatch.as_ref().unwrap().dispatch_id
        );
    }

    #[test]
    fn fleet_phase4_2_session_survives_wave_transition() {
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

        let session = start_fleet_controller_session(
            vec![build, test],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("controller must start");

        let original_session_id = session.session_id.clone();

        let original_wave_id = session.current_wave.wave_id.clone();

        let dispatch = session
            .current_wave
            .dispatch
            .clone()
            .expect("BUILD must dispatch");

        let original_dispatch_id = dispatch.dispatch_id.clone();

        let cycle = single_mission_cycle(
            &dispatch,
            "mission-build",
            "agent-alpha",
            returned_observation("mission-build", "RUN_BUILD", "build"),
        );

        let advanced = advance_fleet_controller_session(
            session,
            &dispatch,
            &cycle,
            vec![fleet_agent("agent-bravo", vec![DockCapability::Test])],
        )
        .expect("BUILD must advance to TEST");

        assert_eq!(
            advanced.session_id, original_session_id,
            "session identity must survive wave transition"
        );

        assert_ne!(
            advanced.current_wave.wave_id, original_wave_id,
            "new scheduler generation requires a new wave id"
        );

        let next_dispatch = advanced
            .current_wave
            .dispatch
            .as_ref()
            .expect("TEST must dispatch");

        assert_ne!(
            next_dispatch.dispatch_id, original_dispatch_id,
            "new wave requires a new dispatch id"
        );
    }

    #[test]
    fn fleet_phase4_2_rejects_dispatch_lineage_substitution() {
        let expected = build_fleet_dispatch_plan(
            vec![fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            )],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("dispatch must build");

        let mut substituted = expected.clone();

        // Keep Mission, Agent and Execution identical.
        // Only the dispatch lineage is changed.
        substituted.dispatch_id = new_lineage_id("dispatch");

        assert_eq!(
            expected.dispatches[0].execution_id,
            substituted.dispatches[0].execution_id
        );

        let error = validate_session_dispatch(&expected, &substituted)
            .expect_err("dispatch lineage substitution must fail closed");

        assert!(
            error.contains("completed dispatch lineage does not match current controller wave"),
            "unexpected error: {error}"
        );
    }
    #[test]
    fn fleet_batch_lineage_flows_recovery_to_telemetry_event() {
        let session = start_fleet_controller_session(
            vec![fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            )],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("session must start");

        let dispatch = session
            .current_wave
            .dispatch
            .as_ref()
            .expect("BUILD must dispatch");

        let execution_id = dispatch.dispatches[0].execution_id.clone();

        let recovery = recover_controller_wave_with_lineage(
            &session,
            vec![AgentMissionReturn {
                mission_id: "mission-build".into(),
                agent_id: Id("agent-alpha".into()),
                observation: returned_observation("mission-build", "RUN_BUILD", "build"),
            }],
        )
        .expect("lineage recovery must succeed");

        assert_eq!(recovery.recovered.len(), 1);

        let item = &recovery.recovered[0];

        assert_eq!(item.lineage.session_id, session.session_id);

        assert_eq!(item.lineage.wave_id, session.current_wave.wave_id);

        assert_eq!(item.lineage.dispatch_id, dispatch.dispatch_id);

        assert_eq!(item.lineage.execution_id, execution_id);

        let cycle = complete_lineage_recovery(&recovery).expect("lineage cycle must complete");

        assert_eq!(cycle.outcomes.len(), 1);

        assert_eq!(
            cycle.outcomes[0].outcome.telemetry.result,
            TelemetryResult::Pass
        );

        assert_eq!(cycle.outcomes[0].outcome.footer.result, MissionState::Pass);

        let events = lineage_event_records(&cycle);

        assert_eq!(events.len(), 1);

        assert_eq!(events[0].topic, "vertex.mission.completed");

        assert_eq!(events[0].lineage.execution_id, execution_id);
    }

    #[test]
    fn fleet_batch_inspector_and_vsp_share_exact_boundary() {
        let session = start_fleet_controller_session(
            vec![fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            )],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("session must start");

        let inspector = build_fleet_inspector_snapshot(&session);

        let checkpoint = create_fleet_vsp_checkpoint(&session);

        assert_eq!(checkpoint.snapshot, inspector);

        assert_eq!(inspector.session_id, session.session_id);

        assert_eq!(inspector.wave_id, session.current_wave.wave_id);

        assert_eq!(inspector.executions.len(), 1);

        validate_fleet_vsp_resume_boundary(&checkpoint, &session)
            .expect("unchanged controller must match VSP boundary");

        let other = start_fleet_controller_session(
            vec![fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            )],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("second session must start");

        let error = validate_fleet_vsp_resume_boundary(&checkpoint, &other)
            .expect_err("foreign controller session must not resume checkpoint");

        assert!(
            error.contains("session lineage mismatch"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn fleet_batch_e2e_build_recovery_telemetry_vsp_and_next_wave() {
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

        let session = start_fleet_controller_session(
            vec![build, test],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("controller must start");

        let original_session_id = session.session_id.clone();

        let original_wave_id = session.current_wave.wave_id.clone();

        let dispatch = session
            .current_wave
            .dispatch
            .clone()
            .expect("BUILD must dispatch");

        let checkpoint = create_fleet_vsp_checkpoint(&session);

        let recovery = recover_controller_wave_with_lineage(
            &session,
            vec![AgentMissionReturn {
                mission_id: "mission-build".into(),
                agent_id: Id("agent-alpha".into()),
                observation: returned_observation("mission-build", "RUN_BUILD", "build"),
            }],
        )
        .expect("BUILD lineage recovery must succeed");

        let lineage_cycle =
            complete_lineage_recovery(&recovery).expect("BUILD telemetry cycle must succeed");

        let events = lineage_event_records(&lineage_cycle);

        assert_eq!(events.len(), 1);

        let base_cycle = MothershipFullCycle {
            outcomes: lineage_cycle
                .outcomes
                .iter()
                .map(|item| item.outcome.clone())
                .collect(),
        };

        let advanced = advance_fleet_controller_session(
            session,
            &dispatch,
            &base_cycle,
            vec![fleet_agent("agent-bravo", vec![DockCapability::Test])],
        )
        .expect("BUILD must advance to TEST");

        assert_eq!(advanced.session_id, original_session_id);

        assert_ne!(advanced.current_wave.wave_id, original_wave_id);

        assert_eq!(
            advanced.current_wave.ready_mission_ids,
            vec!["mission-test".to_string()]
        );

        let error = validate_fleet_vsp_resume_boundary(&checkpoint, &advanced)
            .expect_err("old Wave checkpoint must not match new Wave");

        assert!(
            error.contains("wave lineage mismatch"),
            "unexpected error: {error}"
        );
    }
    #[test]
    fn fleet_live_wire_ingress_raw_json_reaches_lineage_cycle() {
        let session = start_fleet_controller_session(
            vec![fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            )],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("live ingress session must start");

        let dispatch = session
            .current_wave
            .dispatch
            .as_ref()
            .expect("BUILD must dispatch");

        let execution_id = dispatch.dispatches[0].execution_id.clone();

        let payload = r#"
{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "__EXECUTION__",
  "mission_ids": ["mission-build"],
  "runtime": [
    {
      "mission_id": "mission-build",
      "capability": "RUN_BUILD",
      "run": {
        "program": "cargo",
        "args": ["build"],
        "cwd": ".",
        "exit_code": 0,
        "timed_out": false,
        "stdout_ref": "live://stdout/build",
        "stderr_ref": ""
      }
    }
  ],
  "vve": [],
  "changed_files": [],
  "human_gate": {
    "required": false,
    "reasons": []
  },
  "failed_missions": [],
  "denied_missions": []
}
"#
        .replace("__EXECUTION__", &execution_id);

        let returns = genesis_wire_payloads_to_returns(&session, vec![payload])
            .expect("raw Genesis Wire must bind to current execution");

        assert_eq!(returns.len(), 1);

        assert_eq!(returns[0].mission_id, "mission-build");

        assert_eq!(returns[0].agent_id, Id("agent-alpha".into()));

        assert_eq!(
            returns[0].observation.audit_ref.as_deref(),
            Some(format!("genesis://execution/{execution_id}").as_str())
        );

        let recovery = recover_controller_wave_with_lineage(&session, returns)
            .expect("live Wire return must pass recovery");

        assert_eq!(recovery.recovered[0].lineage.execution_id, execution_id);

        let cycle =
            complete_lineage_recovery(&recovery).expect("live Wire must reach telemetry cycle");

        assert_eq!(cycle.outcomes.len(), 1);

        assert_eq!(
            cycle.outcomes[0].outcome.telemetry.result,
            TelemetryResult::Pass
        );
    }

    #[test]
    fn fleet_live_wire_ingress_rejects_stale_execution() {
        let session = start_fleet_controller_session(
            vec![fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            )],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .unwrap();

        let payload = r#"
{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "stale-execution",
  "mission_ids": ["mission-build"],
  "runtime": [],
  "vve": [],
  "changed_files": [],
  "human_gate": {
    "required": false,
    "reasons": []
  },
  "failed_missions": [],
  "denied_missions": []
}
"#
        .to_string();

        let error = genesis_wire_payloads_to_returns(&session, vec![payload])
            .expect_err("stale execution must fail closed");

        assert!(
            error.contains("not in current controller wave"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn fleet_live_wire_ingress_rejects_mission_execution_swap() {
        let session = start_fleet_controller_session(
            vec![fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            )],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .unwrap();

        let execution_id = session.current_wave.dispatch.as_ref().unwrap().dispatches[0]
            .execution_id
            .clone();

        let payload = r#"
{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "__EXECUTION__",
  "mission_ids": ["mission-foreign"],
  "runtime": [],
  "vve": [],
  "changed_files": [],
  "human_gate": {
    "required": false,
    "reasons": []
  },
  "failed_missions": [],
  "denied_missions": []
}
"#
        .replace("__EXECUTION__", &execution_id);

        let error = genesis_wire_payloads_to_returns(&session, vec![payload])
            .expect_err("mission/execution swap must fail closed");

        assert!(
            error.contains("mission does not match execution binding"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn fleet_live_wire_ingress_rejects_multi_mission_execution() {
        let session = start_fleet_controller_session(
            vec![fleet_mission(
                "mission-build",
                DockCapability::Build,
                vec![VerificationRequirement::Build],
            )],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .unwrap();

        let execution_id = session.current_wave.dispatch.as_ref().unwrap().dispatches[0]
            .execution_id
            .clone();

        let payload = r#"
{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "__EXECUTION__",
  "mission_ids": [
    "mission-build",
    "mission-foreign"
  ],
  "runtime": [],
  "vve": [],
  "changed_files": [],
  "human_gate": {
    "required": false,
    "reasons": []
  },
  "failed_missions": [],
  "denied_missions": []
}
"#
        .replace("__EXECUTION__", &execution_id);

        let error = genesis_wire_payloads_to_returns(&session, vec![payload])
            .expect_err("multi-mission execution must fail closed");

        assert!(
            error.contains("exactly one mission per execution"),
            "unexpected error: {error}"
        );
    }
    #[test]
    fn fleet_live_wire_advances_controller_to_next_wave() {
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

        let session = start_fleet_controller_session(
            vec![build, test],
            vec![fleet_agent(
                "agent-alpha",
                vec![DockCapability::Build, DockCapability::Test],
            )],
        )
        .expect("ignition controller must start");

        let original_session_id = session.session_id.clone();

        let completed_dispatch = session
            .current_wave
            .dispatch
            .clone()
            .expect("BUILD must dispatch");

        let execution_id = completed_dispatch.dispatches[0].execution_id.clone();

        let payload = r#"
{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "__EXECUTION__",
  "mission_ids": ["mission-build"],
  "runtime": [
    {
      "mission_id": "mission-build",
      "capability": "RUN_BUILD",
      "run": {
        "program": "cargo",
        "args": ["build"],
        "cwd": ".",
        "exit_code": 0,
        "timed_out": false,
        "stdout_ref": "ignition://stdout/build",
        "stderr_ref": ""
      }
    }
  ],
  "vve": [],
  "changed_files": [],
  "human_gate": {
    "required": false,
    "reasons": []
  },
  "failed_missions": [],
  "denied_missions": []
}
"#
        .replace("__EXECUTION__", &execution_id);

        let returns = genesis_wire_payloads_to_returns(&session, vec![payload])
            .expect("raw machine result must bind");

        let recovery = recover_controller_wave_with_lineage(&session, returns)
            .expect("live return must recover");

        let cycle = complete_lineage_recovery(&recovery).expect("lineage cycle must complete");

        let advanced = advance_controller_after_lineage_cycle(session, &completed_dispatch, &cycle)
            .expect("successful live cycle must advance controller");

        assert_eq!(advanced.session_id, original_session_id);

        assert_eq!(advanced.completed_waves, 1);

        assert_eq!(
            advanced.current_wave.ready_mission_ids,
            vec!["mission-test".to_string()]
        );

        assert!(
            advanced.current_wave.dispatch.is_some(),
            "TEST must become a real next-wave dispatch"
        );
    }
    #[test]
    fn fleet_phase4_controller_runs_build_test_vve_to_completion() {
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

        let missions = vec![build, test, vve];

        // Wave 1: BUILD
        let session = start_fleet_controller_session(
            missions,
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("controller session must start");

        assert_eq!(session.status, FleetControllerSessionStatus::Active);
        assert_eq!(session.completed_waves, 0);
        assert_eq!(
            session.current_wave.ready_mission_ids,
            vec!["mission-build".to_string()]
        );

        let build_dispatch = session
            .current_wave
            .dispatch
            .clone()
            .expect("BUILD must dispatch");

        let build_cycle = single_mission_cycle(
            &build_dispatch,
            "mission-build",
            "agent-alpha",
            returned_observation("mission-build", "RUN_BUILD", "build"),
        );

        // Wave 2: TEST
        let session = advance_fleet_controller_session(
            session,
            &build_dispatch,
            &build_cycle,
            vec![fleet_agent("agent-bravo", vec![DockCapability::Test])],
        )
        .expect("controller must advance to TEST");

        assert_eq!(session.status, FleetControllerSessionStatus::Active);
        assert_eq!(session.completed_waves, 1);
        assert_eq!(
            session.current_wave.ready_mission_ids,
            vec!["mission-test".to_string()]
        );

        let test_dispatch = session
            .current_wave
            .dispatch
            .clone()
            .expect("TEST must dispatch");

        let test_cycle = single_mission_cycle(
            &test_dispatch,
            "mission-test",
            "agent-bravo",
            returned_observation("mission-test", "RUN_TEST", "test"),
        );

        // Wave 3: VVE
        let session = advance_fleet_controller_session(
            session,
            &test_dispatch,
            &test_cycle,
            vec![fleet_agent(
                "agent-charlie",
                vec![DockCapability::VveValidate],
            )],
        )
        .expect("controller must advance to VVE");

        assert_eq!(session.status, FleetControllerSessionStatus::Active);
        assert_eq!(session.completed_waves, 2);
        assert_eq!(
            session.current_wave.ready_mission_ids,
            vec!["mission-vve".to_string()]
        );

        let vve_dispatch = session
            .current_wave
            .dispatch
            .clone()
            .expect("VVE must dispatch");

        let vve_cycle = single_mission_cycle(
            &vve_dispatch,
            "mission-vve",
            "agent-charlie",
            returned_observation("mission-vve", "RUN_VVE", "vve"),
        );

        // No Wave 4: entire DAG must now be terminal PASS.
        let session = advance_fleet_controller_session(session, &vve_dispatch, &vve_cycle, vec![])
            .expect("controller must complete");

        assert_eq!(session.status, FleetControllerSessionStatus::Completed);
        assert_eq!(session.completed_waves, 3);
        assert!(session.current_wave.dispatch.is_none());
        assert!(session.current_wave.ready_mission_ids.is_empty());
        assert!(session.current_wave.blocked_mission_ids.is_empty());
        assert!(session.current_wave.waiting_mission_ids.is_empty());

        assert!(
            session
                .missions
                .iter()
                .all(|mission| mission.unit.state == MissionState::Pass)
        );
    }
    #[test]
    fn fleet_phase3_pass_advances_build_to_test_wave() {
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

        let initial = build_dependency_aware_fleet_wave(
            vec![build.clone(), test.clone()],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("Build wave must schedule");

        let dispatch = initial.dispatch.expect("Build must dispatch");

        let cycle = single_mission_cycle(
            &dispatch,
            "mission-build",
            "agent-alpha",
            returned_observation("mission-build", "RUN_BUILD", "build"),
        );

        let advanced = advance_fleet_after_cycle(
            vec![build, test],
            &dispatch,
            &cycle,
            vec![fleet_agent("agent-bravo", vec![DockCapability::Test])],
        )
        .expect("Fleet must advance to Test");

        let build_state = advanced
            .missions
            .iter()
            .find(|mission| mission.unit.id == Id("mission-build".into()))
            .unwrap()
            .unit
            .state;

        assert_eq!(build_state, MissionState::Pass);

        assert_eq!(
            advanced.next_wave.ready_mission_ids,
            vec!["mission-test".to_string()]
        );

        let next_dispatch = advanced.next_wave.dispatch.expect("Test must dispatch");

        assert_eq!(
            next_dispatch.dispatches[0].request.assignment.mission_id,
            "mission-test"
        );

        assert_eq!(
            next_dispatch.dispatches[0].request.agent.identity.id,
            Id("agent-bravo".into())
        );
    }

    #[test]
    fn fleet_phase3_failure_blocks_downstream_and_stops_launch() {
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

        let initial = build_dependency_aware_fleet_wave(
            vec![build.clone(), test.clone(), vve.clone()],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .expect("Build wave must schedule");

        let dispatch = initial.dispatch.expect("Build must dispatch");

        let mut failed = returned_observation("mission-build", "RUN_BUILD", "build");

        failed.state = GenesisMissionState::Failed;
        failed.runs[0].exit_code = Some(1);
        failed.runs[0].stderr_ref = Some("evidence://stderr/build".into());
        failed.blocker = Some("build failed".into());

        let cycle = single_mission_cycle(&dispatch, "mission-build", "agent-alpha", failed);

        let advanced = advance_fleet_after_cycle(vec![build, test, vve], &dispatch, &cycle, vec![])
            .expect("Failed build must become blocked downstream state");

        let build_state = advanced
            .missions
            .iter()
            .find(|mission| mission.unit.id == Id("mission-build".into()))
            .unwrap()
            .unit
            .state;

        assert_ne!(build_state, MissionState::Pass);

        assert!(advanced.next_wave.ready_mission_ids.is_empty());

        assert_eq!(
            advanced.next_wave.blocked_mission_ids,
            vec!["mission-test".to_string(), "mission-vve".to_string(),]
        );

        assert!(advanced.next_wave.dispatch.is_none());
    }

    #[test]
    fn fleet_phase3_parallel_results_isolate_downstream_branches() {
        let root_a = fleet_mission(
            "mission-root-a",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        let root_b = fleet_mission(
            "mission-root-b",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        let mut child_a = fleet_mission(
            "mission-child-a",
            DockCapability::Test,
            vec![VerificationRequirement::Test],
        );

        child_a.unit.depends_on = vec![Id("mission-root-a".into())];

        let mut child_b = fleet_mission(
            "mission-child-b",
            DockCapability::Test,
            vec![VerificationRequirement::Test],
        );

        child_b.unit.depends_on = vec![Id("mission-root-b".into())];

        let initial = build_dependency_aware_fleet_wave(
            vec![
                root_a.clone(),
                root_b.clone(),
                child_a.clone(),
                child_b.clone(),
            ],
            vec![
                fleet_agent("agent-alpha", vec![DockCapability::Build]),
                fleet_agent("agent-bravo", vec![DockCapability::Build]),
            ],
        )
        .expect("Parallel root wave must schedule");

        let dispatch = initial.dispatch.expect("Both roots must dispatch");

        let mut failed_b = returned_observation("mission-root-b", "RUN_BUILD", "build");

        failed_b.state = GenesisMissionState::Failed;
        failed_b.runs[0].exit_code = Some(1);
        failed_b.blocker = Some("root B failed".into());

        let recovery = recover_multi_agent_dispatch(
            &dispatch,
            vec![
                AgentMissionReturn {
                    mission_id: "mission-root-a".into(),
                    agent_id: Id("agent-alpha".into()),
                    observation: returned_observation("mission-root-a", "RUN_BUILD", "build"),
                },
                AgentMissionReturn {
                    mission_id: "mission-root-b".into(),
                    agent_id: Id("agent-bravo".into()),
                    observation: failed_b,
                },
            ],
        )
        .expect("Parallel roots must recover");

        let cycle = complete_mothership_recovery(&recovery).expect("Parallel cycle must complete");

        let advanced = advance_fleet_after_cycle(
            vec![root_a, root_b, child_a, child_b],
            &dispatch,
            &cycle,
            vec![fleet_agent("agent-charlie", vec![DockCapability::Test])],
        )
        .expect("Fleet must isolate branches");

        assert_eq!(
            advanced.next_wave.ready_mission_ids,
            vec!["mission-child-a".to_string()]
        );

        assert_eq!(
            advanced.next_wave.blocked_mission_ids,
            vec!["mission-child-b".to_string()]
        );

        let next_dispatch = advanced
            .next_wave
            .dispatch
            .expect("Healthy branch must continue");

        assert_eq!(
            next_dispatch.dispatches[0].request.assignment.mission_id,
            "mission-child-a"
        );
    }

    #[test]
    fn fleet_phase3_rejects_missing_cycle_outcome() {
        let mission_a = fleet_mission(
            "mission-a",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        let mission_b = fleet_mission(
            "mission-b",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        let initial = build_dependency_aware_fleet_wave(
            vec![mission_a.clone(), mission_b.clone()],
            vec![
                fleet_agent("agent-alpha", vec![DockCapability::Build]),
                fleet_agent("agent-bravo", vec![DockCapability::Build]),
            ],
        )
        .unwrap();

        let dispatch = initial.dispatch.unwrap();

        let recovery = recover_multi_agent_dispatch(
            &dispatch,
            vec![
                AgentMissionReturn {
                    mission_id: "mission-a".into(),
                    agent_id: Id("agent-alpha".into()),
                    observation: returned_observation("mission-a", "RUN_BUILD", "build"),
                },
                AgentMissionReturn {
                    mission_id: "mission-b".into(),
                    agent_id: Id("agent-bravo".into()),
                    observation: returned_observation("mission-b", "RUN_BUILD", "build"),
                },
            ],
        )
        .unwrap();

        let full_cycle = complete_mothership_recovery(&recovery).unwrap();

        let incomplete_cycle = MothershipFullCycle {
            outcomes: vec![full_cycle.outcomes[0].clone()],
        };

        let error = advance_fleet_after_cycle(
            vec![mission_a, mission_b],
            &dispatch,
            &incomplete_cycle,
            vec![],
        )
        .expect_err("Every dispatched mission must produce an outcome");

        assert!(error.contains("not all dispatched missions produced cycle outcomes"));
    }

    #[test]
    fn fleet_phase3_rejects_outcome_agent_spoofing() {
        let mission = fleet_mission(
            "mission-build",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        let initial = build_dependency_aware_fleet_wave(
            vec![mission.clone()],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .unwrap();

        let dispatch = initial.dispatch.unwrap();

        let mut cycle = single_mission_cycle(
            &dispatch,
            "mission-build",
            "agent-alpha",
            returned_observation("mission-build", "RUN_BUILD", "build"),
        );

        cycle.outcomes[0].agent_id = Id("agent-bravo".into());

        let error = advance_fleet_after_cycle(vec![mission], &dispatch, &cycle, vec![])
            .expect_err("Spoofed cycle outcome must not advance Fleet");

        assert!(error.contains("cycle outcome agent does not match dispatched agent"));
    }

    #[test]
    fn fleet_phase3_rejects_dispatch_mission_missing_from_fleet_state() {
        let mission = fleet_mission(
            "mission-build",
            DockCapability::Build,
            vec![VerificationRequirement::Build],
        );

        let initial = build_dependency_aware_fleet_wave(
            vec![mission],
            vec![fleet_agent("agent-alpha", vec![DockCapability::Build])],
        )
        .unwrap();

        let dispatch = initial.dispatch.unwrap();

        let cycle = single_mission_cycle(
            &dispatch,
            "mission-build",
            "agent-alpha",
            returned_observation("mission-build", "RUN_BUILD", "build"),
        );

        let unrelated = fleet_mission(
            "mission-unrelated",
            DockCapability::Test,
            vec![VerificationRequirement::Test],
        );

        let error = advance_fleet_after_cycle(vec![unrelated], &dispatch, &cycle, vec![])
            .expect_err("Fleet state must contain every completed mission");

        assert!(error.contains("completed dispatch mission is absent from fleet state"));
    }
    #[test]
    fn execution_request_requires_matching_context() {
        let mut context = sample_context();
        context.mission_id = Id("other-mission".into());

        let result = build_execution_request(
            &sample_work_unit(),
            sample_agent(),
            context,
            vec![VerificationRequirement::Build],
        );

        assert!(result.is_err());
    }

    #[test]
    fn execution_request_requires_capability() {
        let mut agent = sample_agent();
        agent
            .grant
            .allowed
            .retain(|cap| cap != &DockCapability::Test);

        let result = build_execution_request(
            &sample_work_unit(),
            agent,
            sample_context(),
            vec![VerificationRequirement::Test],
        );

        assert!(result.is_err());
    }

    #[test]
    fn machine_observation_satisfies_required_build_and_test() {
        let request = request(vec![
            VerificationRequirement::Build,
            VerificationRequirement::Test,
        ]);

        let observation = sample_observation();

        let report = verify_observation(&request, &observation);

        assert!(report.verified);
        assert!(report.build_observed);
        assert!(report.build_passed);
        assert!(report.test_observed);
        assert!(report.test_passed);
    }

    #[test]
    fn claimed_test_without_machine_run_is_not_verified() {
        let request = request(vec![
            VerificationRequirement::Build,
            VerificationRequirement::Test,
        ]);

        let mut observation = sample_observation();
        observation
            .runs
            .retain(|run| !looks_like_test(&run.program, &run.args));

        let report = verify_observation(&request, &observation);

        assert!(!report.verified);
        assert!(report.test_required);
        assert!(!report.test_observed);
        assert!(
            report
                .missing
                .iter()
                .any(|value| value.contains("test observation missing"))
        );
    }

    #[test]
    fn failed_test_is_not_verified() {
        let request = request(vec![VerificationRequirement::Test]);

        let mut observation = sample_observation();

        let test_run = observation
            .runs
            .iter_mut()
            .find(|run| looks_like_test(&run.program, &run.args))
            .unwrap();

        test_run.exit_code = Some(101);

        let report = verify_observation(&request, &observation);

        assert!(!report.verified);
        assert!(report.test_observed);
        assert!(!report.test_passed);
    }

    #[test]
    fn verified_observation_becomes_pass_telemetry() {
        let request = request(vec![
            VerificationRequirement::Build,
            VerificationRequirement::Test,
        ]);

        let telemetry = observation_to_telemetry(&request, &sample_observation());

        assert_eq!(telemetry.result, TelemetryResult::Pass);
        assert_eq!(telemetry.build_result.as_deref(), Some("PASS"));
        assert_eq!(telemetry.test_result.as_deref(), Some("PASS"));
        assert!(!telemetry.evidence.is_empty());
    }

    #[test]
    fn missing_required_test_becomes_unknown_telemetry() {
        let request = request(vec![
            VerificationRequirement::Build,
            VerificationRequirement::Test,
        ]);

        let mut observation = sample_observation();
        observation
            .runs
            .retain(|run| !looks_like_test(&run.program, &run.args));

        let telemetry = observation_to_telemetry(&request, &observation);

        assert_eq!(telemetry.result, TelemetryResult::Unknown);
        assert!(
            telemetry
                .blocker
                .as_deref()
                .unwrap()
                .contains("test observation missing")
        );
    }

    #[test]
    fn scope_violation_forces_fail() {
        let request = request(vec![VerificationRequirement::Build]);

        let mut observation = sample_observation();
        observation.scope_violations = 1;

        let telemetry = observation_to_telemetry(&request, &observation);

        assert_eq!(telemetry.result, TelemetryResult::Fail);
    }

    #[test]
    fn blocker_forces_blocked() {
        let request = request(vec![VerificationRequirement::Build]);

        let mut observation = sample_observation();
        observation.blocker = Some("Human Gate required".into());

        let telemetry = observation_to_telemetry(&request, &observation);

        assert_eq!(telemetry.result, TelemetryResult::Blocked);
    }

    #[test]
    fn telemetry_converts_to_footer() {
        let request = request(vec![
            VerificationRequirement::Build,
            VerificationRequirement::Test,
        ]);

        let telemetry = observation_to_telemetry(&request, &sample_observation());

        let footer = telemetry_to_footer(&telemetry);

        assert_eq!(footer.result, MissionState::Pass);
        assert_eq!(footer.changed_files, vec!["VVE/SOURCE/example.rs"]);
        assert!(!footer.evidence.is_empty());
        assert!(footer.current_blocker.is_none());
    }

    #[test]
    fn pass_requires_machine_evidence() {
        let request = request(vec![VerificationRequirement::Build]);

        let mut telemetry = observation_to_telemetry(&request, &sample_observation());

        assert!(telemetry_is_reviewable(&telemetry));

        telemetry.changed_files.clear();
        telemetry.evidence.clear();

        assert!(!telemetry_is_reviewable(&telemetry));
    }

    #[test]
    fn genesis_observation_converts_runtime_and_vve_evidence() {
        let observation = GenesisObservation {
            mission_id: "mission-1".into(),
            actor: "Hyper Agent".into(),
            capability: "RUN_BUILD".into(),
            state: GenesisMissionState::Completed,
            runs: vec![GenesisRunObservation {
                program: "cargo".into(),
                args: vec!["build".into(), "--workspace".into()],
                cwd: "G:\\Vertex_Project\\Vertex_Studio_AI".into(),
                exit_code: Some(0),
                timed_out: false,
                stdout_ref: Some("evidence://stdout/build-1".into()),
                stderr_ref: None,
            }],
            changeset_id: Some("changeset://vertex/abc".into()),
            changed_files: vec![GenesisChangedFile {
                path: "VVE/SOURCE/example.rs".into(),
                bytes: 128,
                sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".into(),
            }],
            audit_ref: Some("evidence://audit/mission-1".into()),
            blocker: None,
            duration_ms: 900,
        };

        let actual = genesis_observation_to_actual(&observation, Id("agent-1".into()));

        assert_eq!(actual.mission_id.0, "mission-1");
        assert_eq!(actual.agent_id.0, "agent-1");
        assert_eq!(actual.changed_files, vec!["VVE/SOURCE/example.rs"]);
        assert_eq!(actual.runs.len(), 1);
        assert!(actual.runs[0].passed());
        assert!(actual.evidence.len() >= 3);
        assert!(actual.blocker.is_none());
    }

    #[test]
    fn genesis_human_gate_becomes_blocker_and_intervention() {
        let observation = GenesisObservation {
            mission_id: "mission-2".into(),
            actor: "Hyper Agent".into(),
            capability: "PROMOTE_VVE".into(),
            state: GenesisMissionState::HumanGateRequired,
            runs: vec![],
            changeset_id: None,
            changed_files: vec![],
            audit_ref: Some("evidence://audit/mission-2".into()),
            blocker: None,
            duration_ms: 10,
        };

        let actual = genesis_observation_to_actual(&observation, Id("agent-1".into()));

        assert_eq!(actual.human_interventions, 1);
        assert!(actual.blocker.as_deref().unwrap().contains("Human Gate"));
    }
    #[test]
    fn genesis_build_flows_all_the_way_to_ard_pass() {
        let request = request(vec![VerificationRequirement::Build]);

        let genesis = GenesisObservation {
            mission_id: "mission-1".into(),
            actor: "Hyper Agent".into(),
            capability: "RUN_BUILD".into(),
            state: GenesisMissionState::Completed,
            runs: vec![GenesisRunObservation {
                program: "cargo".into(),
                args: vec!["build".into(), "--workspace".into()],
                cwd: "G:\\Vertex_Project\\Vertex_Studio_AI".into(),
                exit_code: Some(0),
                timed_out: false,
                stdout_ref: Some("evidence://stdout/build-pass".into()),
                stderr_ref: None,
            }],
            changeset_id: Some("changeset://vertex/build-pass".into()),
            changed_files: vec![GenesisChangedFile {
                path: "VVE/SOURCE/example.rs".into(),
                bytes: 256,
                sha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".into(),
            }],
            audit_ref: Some("evidence://audit/build-pass".into()),
            blocker: None,
            duration_ms: 1500,
        };

        let actual = genesis_observation_to_actual(&genesis, request.agent.identity.id.clone());

        let verification = verify_observation(&request, &actual);
        assert!(verification.verified);
        assert!(verification.build_required);
        assert!(verification.build_observed);
        assert!(verification.build_passed);

        let telemetry = observation_to_telemetry(&request, &actual);

        assert_eq!(telemetry.result, TelemetryResult::Pass);
        assert_eq!(telemetry.build_result.as_deref(), Some("PASS"));
        assert!(telemetry_is_reviewable(&telemetry));

        let footer = telemetry_to_footer(&telemetry);

        assert_eq!(footer.result, MissionState::Pass);
        assert_eq!(footer.changed_files, vec!["VVE/SOURCE/example.rs"]);
        assert!(!footer.evidence.is_empty());
        assert!(footer.current_blocker.is_none());
    }

    #[test]
    fn wire_v1_fail_safe_rejects_unknown_runtime_mission() {
        let payload = r#"
{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "execution-unknown-mission",
  "mission_ids": ["mission-1"],
  "runtime": [
    {
      "mission_id": "mission-UNKNOWN",
      "capability": "RUN_BUILD",
      "run": {
        "program": "cargo",
        "args": ["build", "--workspace"],
        "cwd": "G:\\Vertex_Project\\Vertex_Studio_AI",
        "exit_code": 0,
        "timed_out": false,
        "stdout_ref": "build ok",
        "stderr_ref": ""
      }
    }
  ],
  "vve": [],
  "changed_files": [],
  "human_gate": {
    "required": false,
    "reasons": []
  },
  "failed_missions": [],
  "denied_missions": []
}
"#;

        let wire = receive_genesis_observation_v1(payload).expect("wire itself must decode");

        let error = genesis_wire_v1_to_observations(&wire)
            .expect_err("unknown runtime mission must be rejected");

        assert!(
            error.contains("unknown mission"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn wire_v1_fail_safe_rejects_exit_code_outside_i32_range() {
        let payload = r#"
{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "execution-exit-overflow",
  "mission_ids": ["mission-1"],
  "runtime": [
    {
      "mission_id": "mission-1",
      "capability": "RUN_BUILD",
      "run": {
        "program": "cargo",
        "args": ["build", "--workspace"],
        "cwd": "G:\\Vertex_Project\\Vertex_Studio_AI",
        "exit_code": 2147483648,
        "timed_out": false,
        "stdout_ref": null,
        "stderr_ref": null
      }
    }
  ],
  "vve": [],
  "changed_files": [],
  "human_gate": {
    "required": false,
    "reasons": []
  },
  "failed_missions": [],
  "denied_missions": []
}
"#;

        let wire = receive_genesis_observation_v1(payload).expect("wire itself must decode");

        let error = genesis_wire_v1_to_observations(&wire)
            .expect_err("out-of-range exit code must be rejected");

        assert!(
            error.contains("out of i32 range"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn wire_v1_fail_safe_failed_mission_never_reaches_ard_pass() {
        let request = request(vec![]);

        let payload = r#"
{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "execution-failed-mission",
  "mission_ids": ["mission-1"],
  "runtime": [],
  "vve": [],
  "changed_files": [],
  "human_gate": {
    "required": false,
    "reasons": []
  },
  "failed_missions": ["mission-1"],
  "denied_missions": []
}
"#;

        let wire =
            receive_genesis_observation_v1(payload).expect("failed mission wire must decode");

        let observations =
            genesis_wire_v1_to_observations(&wire).expect("failed mission wire must normalize");

        assert_eq!(observations.len(), 1);
        assert_eq!(observations[0].state, GenesisMissionState::Failed);
        assert!(observations[0].blocker.is_some());

        let actual =
            genesis_observation_to_actual(&observations[0], request.agent.identity.id.clone());

        assert!(actual.blocker.is_some());

        let telemetry = observation_to_telemetry(&request, &actual);

        assert_ne!(
            telemetry.result,
            TelemetryResult::Pass,
            "failed Genesis mission must never become PASS telemetry"
        );

        let footer = telemetry_to_footer(&telemetry);

        assert_ne!(
            footer.result,
            MissionState::Pass,
            "failed Genesis mission must never become ARD PASS"
        );

        assert!(footer.current_blocker.is_some());
    }

    #[test]
    fn wire_v1_fail_safe_human_gate_reaches_ard_blocked() {
        let request = request(vec![]);

        let payload = r#"
{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "execution-human-gate",
  "mission_ids": ["mission-1"],
  "runtime": [],
  "vve": [],
  "changed_files": [],
  "human_gate": {
    "required": true,
    "reasons": [
      "Owner approval required before promotion"
    ]
  },
  "failed_missions": [],
  "denied_missions": []
}
"#;

        let wire = receive_genesis_observation_v1(payload).expect("Human Gate wire must decode");

        let observations =
            genesis_wire_v1_to_observations(&wire).expect("Human Gate wire must normalize");

        assert_eq!(observations.len(), 1);

        assert_eq!(
            observations[0].state,
            GenesisMissionState::HumanGateRequired
        );

        assert!(
            observations[0]
                .blocker
                .as_deref()
                .unwrap()
                .contains("Owner approval required")
        );

        let actual =
            genesis_observation_to_actual(&observations[0], request.agent.identity.id.clone());

        assert_eq!(actual.human_interventions, 1);
        assert!(actual.blocker.is_some());

        let telemetry = observation_to_telemetry(&request, &actual);

        assert_eq!(telemetry.result, TelemetryResult::Blocked);

        assert_eq!(telemetry.human_interventions, 1);

        let footer = telemetry_to_footer(&telemetry);

        assert_eq!(footer.result, MissionState::Blocked);

        assert!(footer.current_blocker.is_some());
    }
    #[test]
    fn multi_mission_isolation_separates_runtime_and_state() {
        let payload = r#"
{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "execution-isolation-runtime",
  "mission_ids": ["mission-build", "mission-test"],
  "runtime": [
    {
      "mission_id": "mission-build",
      "capability": "RUN_BUILD",
      "run": {
        "program": "cargo",
        "args": ["build", "--workspace"],
        "cwd": "G:\\Vertex_Project\\Vertex_Studio_AI",
        "exit_code": 0,
        "timed_out": false,
        "stdout_ref": "build ok",
        "stderr_ref": ""
      }
    },
    {
      "mission_id": "mission-test",
      "capability": "RUN_TEST",
      "run": {
        "program": "cargo",
        "args": ["test", "--workspace"],
        "cwd": "G:\\Vertex_Project\\Vertex_Studio_AI",
        "exit_code": 1,
        "timed_out": false,
        "stdout_ref": "",
        "stderr_ref": "test failed"
      }
    }
  ],
  "vve": [],
  "changed_files": [],
  "human_gate": {
    "required": false,
    "reasons": []
  },
  "failed_missions": [],
  "denied_missions": []
}
"#;

        let wire = receive_genesis_observation_v1(payload).expect("wire must decode");

        let observations = genesis_wire_v1_to_observations(&wire).expect("wire must normalize");

        assert_eq!(observations.len(), 2);

        let build = observations
            .iter()
            .find(|item| item.mission_id == "mission-build")
            .unwrap();

        let test = observations
            .iter()
            .find(|item| item.mission_id == "mission-test")
            .unwrap();

        assert_eq!(build.state, GenesisMissionState::Completed);
        assert_eq!(build.runs.len(), 1);
        assert_eq!(build.runs[0].args, vec!["build", "--workspace"]);
        assert_eq!(build.runs[0].exit_code, Some(0));
        assert!(build.blocker.is_none());

        assert_eq!(test.state, GenesisMissionState::Failed);
        assert_eq!(test.runs.len(), 1);
        assert_eq!(test.runs[0].args, vec!["test", "--workspace"]);
        assert_eq!(test.runs[0].exit_code, Some(1));
        assert!(test.blocker.is_some());

        assert!(
            build
                .runs
                .iter()
                .all(|run| !run.args.iter().any(|arg| arg == "test"))
        );

        assert!(
            test.runs
                .iter()
                .all(|run| !run.args.iter().any(|arg| arg == "build"))
        );
    }

    #[test]
    fn multi_mission_isolation_keeps_vve_changeset_on_target_mission() {
        let payload = r#"
{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "execution-isolation-vve",
  "mission_ids": ["mission-build", "mission-vve"],
  "runtime": [
    {
      "mission_id": "mission-build",
      "capability": "RUN_BUILD",
      "run": {
        "program": "cargo",
        "args": ["build"],
        "cwd": "G:\\Vertex_Project\\Vertex_Studio_AI",
        "exit_code": 0,
        "timed_out": false,
        "stdout_ref": null,
        "stderr_ref": null
      }
    }
  ],
  "vve": [
    {
      "mission_id": "mission-vve",
      "capability": "VVE_PROMOTE",
      "changeset_id": "changeset://vertex/isolation-vve",
      "state": "COMPLETED"
    }
  ],
  "changed_files": [],
  "human_gate": {
    "required": false,
    "reasons": []
  },
  "failed_missions": [],
  "denied_missions": []
}
"#;

        let wire = receive_genesis_observation_v1(payload).expect("wire must decode");

        let observations = genesis_wire_v1_to_observations(&wire).expect("wire must normalize");

        let build = observations
            .iter()
            .find(|item| item.mission_id == "mission-build")
            .unwrap();

        let vve = observations
            .iter()
            .find(|item| item.mission_id == "mission-vve")
            .unwrap();

        assert!(build.changeset_id.is_none());

        assert_eq!(
            vve.changeset_id.as_deref(),
            Some("changeset://vertex/isolation-vve")
        );

        assert_eq!(vve.capability, "VVE_PROMOTE");
    }

    #[test]
    fn multi_mission_isolation_assigns_changed_files_only_to_unique_vve_mission() {
        let payload = r#"
{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "execution-isolation-files",
  "mission_ids": ["mission-build", "mission-vve"],
  "runtime": [
    {
      "mission_id": "mission-build",
      "capability": "RUN_BUILD",
      "run": {
        "program": "cargo",
        "args": ["build"],
        "cwd": "G:\\Vertex_Project\\Vertex_Studio_AI",
        "exit_code": 0,
        "timed_out": false,
        "stdout_ref": null,
        "stderr_ref": null
      }
    }
  ],
  "vve": [
    {
      "mission_id": "mission-vve",
      "capability": "VVE_WRITE",
      "changeset_id": "changeset://vertex/isolation-files",
      "state": "COMPLETED"
    }
  ],
  "changed_files": [
    {
      "path": "VVE/SOURCE/isolation.rs",
      "bytes": 128,
      "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
  ],
  "human_gate": {
    "required": false,
    "reasons": []
  },
  "failed_missions": [],
  "denied_missions": []
}
"#;

        let wire = receive_genesis_observation_v1(payload).expect("wire must decode");

        let observations = genesis_wire_v1_to_observations(&wire).expect("wire must normalize");

        let build = observations
            .iter()
            .find(|item| item.mission_id == "mission-build")
            .unwrap();

        let vve = observations
            .iter()
            .find(|item| item.mission_id == "mission-vve")
            .unwrap();

        assert!(build.changed_files.is_empty());

        assert_eq!(vve.changed_files.len(), 1);
        assert_eq!(vve.changed_files[0].path, "VVE/SOURCE/isolation.rs");
    }

    #[test]
    fn multi_mission_isolation_rejects_ambiguous_changed_files() {
        let payload = r#"
{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "execution-isolation-ambiguous-files",
  "mission_ids": ["mission-vve-a", "mission-vve-b"],
  "runtime": [],
  "vve": [
    {
      "mission_id": "mission-vve-a",
      "capability": "VVE_WRITE",
      "changeset_id": "changeset://vertex/a",
      "state": "COMPLETED"
    },
    {
      "mission_id": "mission-vve-b",
      "capability": "VVE_WRITE",
      "changeset_id": "changeset://vertex/b",
      "state": "COMPLETED"
    }
  ],
  "changed_files": [
    {
      "path": "VVE/SOURCE/ambiguous.rs",
      "bytes": 256,
      "sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    }
  ],
  "human_gate": {
    "required": false,
    "reasons": []
  },
  "failed_missions": [],
  "denied_missions": []
}
"#;

        let wire = receive_genesis_observation_v1(payload).expect("wire itself must decode");

        let error = genesis_wire_v1_to_observations(&wire)
            .expect_err("ambiguous changed files must fail closed");

        assert!(
            error.contains("cannot be assigned unambiguously"),
            "unexpected error: {error}"
        );
    }
    #[test]
    fn genesis_wire_v1_flows_all_the_way_to_ard_pass() {
        let unit = sample_work_unit();

        let request = build_execution_request(
            &unit,
            sample_agent(),
            sample_context(),
            vec![
                VerificationRequirement::Build,
                VerificationRequirement::Test,
            ],
        )
        .unwrap();

        let payload = format!(
            r#"{{
  "schema": "vertex.genesis.observation.v1",
  "execution_id": "execution-wire-ard-e2e",
  "mission_ids": ["{}"],
  "runtime": [
    {{
      "mission_id": "{}",
      "capability": "ARD_EXECUTION",
      "run": {{
        "program": "cargo",
        "args": ["build", "--workspace"],
        "cwd": "G:\\Vertex_Project\\Vertex_Studio_AI",
        "exit_code": 0,
        "timed_out": false,
        "stdout_ref": "evidence://stdout/build",
        "stderr_ref": null
      }}
    }},
    {{
      "mission_id": "{}",
      "capability": "ARD_EXECUTION",
      "run": {{
        "program": "cargo",
        "args": ["test", "--workspace"],
        "cwd": "G:\\Vertex_Project\\Vertex_Studio_AI",
        "exit_code": 0,
        "timed_out": false,
        "stdout_ref": "evidence://stdout/test",
        "stderr_ref": null
      }}
    }}
  ],
  "vve": [
    {{
      "mission_id": "{}",
      "capability": "ARD_EXECUTION",
      "changeset_id": "changeset://vertex/wire-ard-e2e",
      "state": "COMPLETED"
    }}
  ],
  "changed_files": [
    {{
      "path": "VVE/SOURCE/wire_ard_e2e.rs",
      "bytes": 512,
      "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }}
  ],
  "human_gate": {{
    "required": false,
    "reasons": []
  }},
  "failed_missions": [],
  "denied_missions": []
}}"#,
            unit.id.0, unit.id.0, unit.id.0, unit.id.0,
        );

        // Real Genesis Wire boundary.
        let wire =
            receive_genesis_observation_v1(&payload).expect("locked Genesis Wire V1 must decode");

        assert_eq!(wire.schema, GENESIS_OBSERVATION_WIRE_V1);

        // Wire -> internal mission observations.
        let observations =
            genesis_wire_v1_to_observations(&wire).expect("Genesis Wire V1 must normalize");

        assert_eq!(observations.len(), 1);

        let genesis = &observations[0];

        assert_eq!(genesis.mission_id, unit.id.0);
        assert_eq!(genesis.state, GenesisMissionState::Completed);
        assert_eq!(genesis.runs.len(), 2);
        assert_eq!(
            genesis.changeset_id.as_deref(),
            Some("changeset://vertex/wire-ard-e2e")
        );
        assert_eq!(genesis.changed_files.len(), 1);

        // Existing internal bridge.
        let actual = genesis_observation_to_actual(genesis, request.agent.identity.id.clone());

        assert_eq!(actual.runs.len(), 2);
        assert!(actual.runs.iter().all(RunObservation::passed));
        assert_eq!(actual.changed_files.len(), 1);
        assert!(!actual.evidence.is_empty());

        // Existing verification contract.
        let report = verify_observation(&request, &actual);

        assert!(report.build_required);
        assert!(report.test_required);
        assert!(report.build_observed);
        assert!(report.test_observed);
        assert!(report.build_passed);
        assert!(report.test_passed);
        assert!(report.evidence_present);
        assert!(report.changed_files_present);
        assert!(report.verified);
        assert!(report.missing.is_empty());

        // Existing telemetry bridge.
        let telemetry = observation_to_telemetry(&request, &actual);

        assert_eq!(telemetry.result, TelemetryResult::Pass);
        assert_eq!(telemetry.build_result.as_deref(), Some("PASS"));
        assert_eq!(telemetry.test_result.as_deref(), Some("PASS"));
        assert_eq!(telemetry.changed_files.len(), 1);

        // Existing ARD footer boundary.
        let footer = telemetry_to_footer(&telemetry);

        assert_eq!(footer.result, MissionState::Pass);
        assert!(!footer.scope_violation);
        assert!(footer.current_blocker.is_none());
        assert!(!footer.evidence.is_empty());
    }
    #[test]
    fn genesis_multi_run_build_and_test_flow_to_ard_pass() {
        let unit = sample_work_unit();

        let request = build_execution_request(
            &unit,
            sample_agent(),
            sample_context(),
            vec![
                VerificationRequirement::Build,
                VerificationRequirement::Test,
            ],
        )
        .unwrap();

        let genesis = GenesisObservation {
            mission_id: unit.id.0.clone(),
            actor: "genesis-harness".into(),
            capability: "ARD_EXECUTION".into(),
            state: GenesisMissionState::Completed,

            runs: vec![
                GenesisRunObservation {
                    program: "cargo".into(),
                    args: vec!["build".into(), "--workspace".into()],
                    cwd: "G:\\Vertex_Project\\Vertex_Studio_AI".into(),
                    exit_code: Some(0),
                    timed_out: false,
                    stdout_ref: Some("evidence://stdout/build".into()),
                    stderr_ref: None,
                },
                GenesisRunObservation {
                    program: "cargo".into(),
                    args: vec!["test".into(), "--workspace".into()],
                    cwd: "G:\\Vertex_Project\\Vertex_Studio_AI".into(),
                    exit_code: Some(0),
                    timed_out: false,
                    stdout_ref: Some("evidence://stdout/test".into()),
                    stderr_ref: None,
                },
            ],

            changeset_id: Some("changeset://vertex/multi-run".into()),

            changed_files: vec![GenesisChangedFile {
                path: "VVE/SOURCE/multi_run.rs".into(),
                bytes: 512,
                sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".into(),
            }],

            audit_ref: Some("evidence://audit/multi-run".into()),
            blocker: None,
            duration_ms: 2000,
        };

        let actual = genesis_observation_to_actual(&genesis, request.agent.identity.id.clone());

        assert_eq!(actual.runs.len(), 2);
        assert!(actual.runs.iter().all(RunObservation::passed));

        let report = verify_observation(&request, &actual);

        assert!(report.build_required);
        assert!(report.test_required);

        assert!(report.build_observed);
        assert!(report.test_observed);

        assert!(report.build_passed);
        assert!(report.test_passed);

        assert!(report.evidence_present);
        assert!(report.changed_files_present);

        assert!(report.verified);
        assert!(report.missing.is_empty());

        let telemetry = observation_to_telemetry(&request, &actual);

        assert_eq!(telemetry.result, TelemetryResult::Pass);
        assert_eq!(telemetry.changed_files.len(), 1);
        assert_eq!(telemetry.build_result.as_deref(), Some("PASS"));
        assert_eq!(telemetry.test_result.as_deref(), Some("PASS"));

        let footer = telemetry_to_footer(&telemetry);

        assert_eq!(footer.result, MissionState::Pass);
        assert!(!footer.scope_violation);
        assert!(footer.current_blocker.is_none());
    }
    #[test]
    fn genesis_human_gate_flows_all_the_way_to_ard_blocked() {
        let request = request(vec![]);

        let genesis = GenesisObservation {
            mission_id: "mission-1".into(),
            actor: "Hyper Agent".into(),
            capability: "PROMOTE_VVE".into(),
            state: GenesisMissionState::HumanGateRequired,
            runs: vec![],
            changeset_id: Some("changeset://vertex/waiting-human".into()),
            changed_files: vec![GenesisChangedFile {
                path: "VVE/SOURCE/example.rs".into(),
                bytes: 256,
                sha256: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc".into(),
            }],
            audit_ref: Some("evidence://audit/waiting-human".into()),
            blocker: Some("Owner approval required before VVE promotion".into()),
            duration_ms: 25,
        };

        let actual = genesis_observation_to_actual(&genesis, request.agent.identity.id.clone());

        assert_eq!(actual.human_interventions, 1);
        assert!(actual.blocker.is_some());

        let telemetry = observation_to_telemetry(&request, &actual);

        assert_eq!(telemetry.result, TelemetryResult::Blocked);
        assert_eq!(telemetry.human_interventions, 1);
        assert!(
            telemetry
                .blocker
                .as_deref()
                .unwrap()
                .contains("Owner approval required")
        );

        let footer = telemetry_to_footer(&telemetry);

        assert_eq!(footer.result, MissionState::Blocked);
        assert!(footer.current_blocker.is_some());
        assert!(!footer.evidence.is_empty());
    }
    #[test]
    fn failed_telemetry_is_always_reviewable() {
        let request = request(vec![VerificationRequirement::Build]);

        let mut telemetry = observation_to_telemetry(&request, &sample_observation());

        telemetry.result = TelemetryResult::Fail;
        telemetry.changed_files.clear();
        telemetry.evidence.clear();
        telemetry.build_result = Some("FAIL".into());

        assert!(telemetry_is_reviewable(&telemetry));
    }

    #[test]
    fn fleet_phase4_6_idle_agent_survives_live_wave_transition() {
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

        // Bravo is intentionally idle in Wave 1. Before Phase 4.6 the live
        // advance path lost Bravo because only dispatched Agents were reused.
        let session = start_fleet_controller_session(
            vec![build, test],
            vec![
                fleet_agent("agent-alpha", vec![DockCapability::Build]),
                fleet_agent("agent-bravo", vec![DockCapability::Test]),
            ],
        )
        .expect("controller session must start");

        assert_eq!(session.agent_pool.len(), 2);

        let dispatch = session
            .current_wave
            .dispatch
            .clone()
            .expect("BUILD must dispatch");

        assert_eq!(dispatch.dispatches.len(), 1);
        assert_eq!(
            dispatch.dispatches[0].request.agent.identity.id,
            Id("agent-alpha".into())
        );

        let recovery = recover_controller_wave_with_lineage(
            &session,
            vec![AgentMissionReturn {
                mission_id: "mission-build".into(),
                agent_id: Id("agent-alpha".into()),
                observation: returned_observation("mission-build", "RUN_BUILD", "build"),
            }],
        )
        .expect("BUILD lineage recovery must succeed");

        let cycle =
            complete_lineage_recovery(&recovery).expect("BUILD lineage cycle must complete");

        let advanced = advance_controller_after_lineage_cycle(session, &dispatch, &cycle)
            .expect("idle TEST agent must survive into Wave 2");

        assert_eq!(advanced.agent_pool.len(), 2);
        assert_eq!(
            advanced.current_wave.ready_mission_ids,
            vec!["mission-test".to_string()]
        );

        let next_dispatch = advanced
            .current_wave
            .dispatch
            .as_ref()
            .expect("TEST must dispatch");

        assert_eq!(next_dispatch.dispatches.len(), 1);
        assert_eq!(
            next_dispatch.dispatches[0].request.agent.identity.id,
            Id("agent-bravo".into())
        );
    }
}

// ================================================================
// VERTEX LIVE WIRE INGRESS V1
//
// Production invariant:
//
//   1 Genesis Wire payload
//       == 1 execution
//       == 1 mission
//       == 1 currently dispatched Hyper Agent
//
// Agent identity is NOT trusted from transport input.
// It is derived from the current dispatch by execution_id.
//
// This converts untrusted Genesis Wire JSON into a strongly-bound
// AgentMissionReturn set suitable for the existing Mothership
// recovery / anti-replay / lineage pipeline.
// ================================================================

pub fn genesis_wire_payloads_to_returns(
    session: &FleetControllerSession,
    payloads: Vec<String>,
) -> Result<Vec<AgentMissionReturn>, String> {
    use std::collections::{HashMap, HashSet};

    let plan =
        session.current_wave.dispatch.as_ref().ok_or_else(|| {
            "live Genesis ingress requires an active controller dispatch".to_string()
        })?;

    if payloads.len() != plan.dispatches.len() {
        return Err(format!(
            "live Genesis ingress payload count mismatch: expected={} actual={}",
            plan.dispatches.len(),
            payloads.len()
        ));
    }

    let dispatch_by_execution: HashMap<&str, &AgentMissionDispatch> = plan
        .dispatches
        .iter()
        .map(|dispatch| (dispatch.execution_id.as_str(), dispatch))
        .collect();

    let mut seen_executions = HashSet::new();

    let mut returns = Vec::with_capacity(payloads.len());

    for payload in payloads {
        // Locked schema decode.
        let wire = receive_genesis_observation_v1(&payload)?;

        // One execution identity cannot safely represent multiple
        // independently dispatched missions.
        if wire.mission_ids.len() != 1 {
            return Err(format!(
                "live Genesis ingress requires exactly one mission per execution: execution={} missions={}",
                wire.execution_id,
                wire.mission_ids.len()
            ));
        }

        if !seen_executions.insert(wire.execution_id.clone()) {
            return Err(format!(
                "duplicate live Genesis execution payload: {}",
                wire.execution_id
            ));
        }

        let dispatch = dispatch_by_execution
            .get(wire.execution_id.as_str())
            .copied()
            .ok_or_else(|| {
                format!(
                    "live Genesis execution is not in current controller wave: {}",
                    wire.execution_id
                )
            })?;

        let expected_mission = dispatch.request.assignment.mission_id.as_str();

        let wire_mission = wire.mission_ids[0].as_str();

        if wire_mission != expected_mission {
            return Err(format!(
                "live Genesis mission does not match execution binding: execution={} expected={} actual={}",
                wire.execution_id, expected_mission, wire_mission
            ));
        }

        // Existing converter also stamps:
        //
        // genesis://execution/<wire.execution_id>
        //
        // into observation.audit_ref.
        let mut observations = genesis_wire_v1_to_observations(&wire)?;

        if observations.len() != 1 {
            return Err(format!(
                "live Genesis normalization produced invalid observation count: execution={} count={}",
                wire.execution_id,
                observations.len()
            ));
        }

        let observation = observations
            .pop()
            .expect("observation count was validated above");

        // Critical:
        // Agent identity comes from the trusted current dispatch.
        let agent_id = dispatch.request.agent.identity.id.clone();

        returns.push(AgentMissionReturn {
            mission_id: expected_mission.to_string(),

            agent_id,

            observation,
        });
    }

    Ok(returns)
}

// ================================================================
// VERTEX CONTROLLER LIVE ADVANCE V1
//
// LineageFullCycle
//      ↓
// authoritative MothershipFullCycle projection
//      ↓
// existing controller validation
//      ↓
// ARD state transition
//      ↓
// NEXT WAVE
//
// Current dispatched Hyper Agents are returned to the reusable
// scheduling pool after successful completion.
// ================================================================

pub fn advance_controller_after_lineage_cycle(
    session: FleetControllerSession,
    completed_dispatch: &MultiAgentDispatchPlan,
    cycle: &LineageFullCycle,
) -> Result<FleetControllerSession, String> {
    let base_cycle = MothershipFullCycle {
        outcomes: cycle
            .outcomes
            .iter()
            .map(|item| item.outcome.clone())
            .collect(),
    };

    let reusable_agents = completed_dispatch
        .dispatches
        .iter()
        .map(|dispatch| dispatch.request.agent.clone())
        .collect();

    advance_fleet_controller_session(session, completed_dispatch, &base_cycle, reusable_agents)
}
