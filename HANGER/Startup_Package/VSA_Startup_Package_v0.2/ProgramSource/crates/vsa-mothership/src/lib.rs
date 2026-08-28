use vsa_foundation::Id;
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FacilityKind {
    CommandBridge,
    Base,
    Dock,
    Warehouse,
    Hangar,
    Catapult,
    Observatory,
    Arsenal,
    ControlTower,
    SupplyDepot,
    Library,
    ProvingGround,
    Quarantine,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Facility {
    pub id: Id,
    pub name: String,
    pub kind: FacilityKind,
    pub capabilities: Vec<String>,
}
pub fn default_mothership() -> Vec<Facility> {
    use FacilityKind::*;
    [
        (
            "Command Bridge",
            CommandBridge,
            vec!["ARD", "Party", "Human Gate"],
        ),
        (
            "Dock",
            Dock,
            vec!["Build", "Repair", "Migration", "Validation"],
        ),
        (
            "Warehouse",
            Warehouse,
            vec!["Models", "Assets", "Packages", "RCC"],
        ),
        ("Hangar", Hangar, vec!["Agents", "Drones", "Portable Units"]),
        ("Catapult", Catapult, vec!["Mission Dispatch"]),
        (
            "Observatory",
            Observatory,
            vec!["Telemetry", "Benchmark", "Failure Analysis"],
        ),
        (
            "Arsenal",
            Arsenal,
            vec!["Code", "VXN", "UI", "Package Build"],
        ),
        (
            "Control Tower",
            ControlTower,
            vec!["Provider", "Runtime", "Jobs", "Ports"],
        ),
        (
            "Supply Depot",
            SupplyDepot,
            vec!["Capability on Demand", "Hot Reinforcement"],
        ),
        ("Library", Library, vec!["VCC", "Knowledge", "Genesis"]),
        (
            "Proving Ground",
            ProvingGround,
            vec!["LLM Benchmark", "RCC A/B Test"],
        ),
        (
            "Quarantine",
            Quarantine,
            vec!["Sandbox", "Untrusted Cartridge"],
        ),
    ]
    .into_iter()
    .map(|(n, k, c)| Facility {
        id: Id::new("facility"),
        name: n.into(),
        kind: k,
        capabilities: c.into_iter().map(str::to_string).collect(),
    })
    .collect()
}

// ================================================================
// VERTEX MOTHERSHIP BRIDGE DOCK V1
//
// Hyper Agent Return
//      ↓
// Mothership
//      ↓
// Vertex Bridge
//      ↓
// Anti-Replay / Execution Lineage
//      ↓
// Recovery / Telemetry / Event / Inspector / VSP
//
// vsa-mothership owns the entry point.
// vsa-vertex-bridge remains the execution-integrity authority.
// ================================================================

pub mod vertex_bridge_dock {
    use vsa_vertex_bridge::{
        AgentMissionReturn, FleetControllerSession, FleetInspectorSnapshot, FleetVspCheckpoint,
        LineageEventRecord, LineageFullCycle, LineageRecovery, build_fleet_inspector_snapshot,
        complete_lineage_recovery, create_fleet_vsp_checkpoint, lineage_event_records,
        recover_controller_wave_with_lineage, validate_fleet_vsp_resume_boundary,
    };

    pub const MOTHERSHIP_BRIDGE_SCHEMA: &str = "vertex.mothership.bridge.v1";

    #[derive(Debug, Clone, PartialEq)]
    pub struct MothershipDockCycle {
        pub recovery: LineageRecovery,
        pub cycle: LineageFullCycle,
        pub events: Vec<LineageEventRecord>,
        pub inspector: FleetInspectorSnapshot,
        pub checkpoint: FleetVspCheckpoint,
    }

    /// Primary Hyper Agent return entry point.
    ///
    /// The mothership does not duplicate Bridge security logic.
    /// It delegates:
    ///
    /// - mission binding
    /// - agent binding
    /// - observation binding
    /// - anti-replay
    /// - execution lineage
    ///
    /// to vsa-vertex-bridge, then exposes the resulting observability
    /// artifacts to the rest of the mothership.
    pub fn accept_hyper_agent_returns(
        session: &FleetControllerSession,
        returns: Vec<AgentMissionReturn>,
    ) -> Result<MothershipDockCycle, String> {
        let recovery = recover_controller_wave_with_lineage(session, returns)?;

        let cycle = complete_lineage_recovery(&recovery)?;

        let events = lineage_event_records(&cycle);

        let inspector = build_fleet_inspector_snapshot(session);

        let checkpoint = create_fleet_vsp_checkpoint(session);

        Ok(MothershipDockCycle {
            recovery,
            cycle,
            events,
            inspector,
            checkpoint,
        })
    }

    /// Read-only Console Inspector projection.
    pub fn inspector_snapshot(session: &FleetControllerSession) -> FleetInspectorSnapshot {
        build_fleet_inspector_snapshot(session)
    }

    /// VSP save-point boundary generated directly from the
    /// current controller lineage.
    pub fn checkpoint(session: &FleetControllerSession) -> FleetVspCheckpoint {
        create_fleet_vsp_checkpoint(session)
    }

    /// Fail-closed resume validation.
    pub fn validate_resume(
        checkpoint: &FleetVspCheckpoint,
        session: &FleetControllerSession,
    ) -> Result<(), String> {
        validate_fleet_vsp_resume_boundary(checkpoint, session)
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn mothership_bridge_schema_is_locked() {
            assert_eq!(MOTHERSHIP_BRIDGE_SCHEMA, "vertex.mothership.bridge.v1");
        }

        #[test]
        fn mothership_bridge_contract_compiles_against_vertex_bridge() {
            let _accept: fn(
                &FleetControllerSession,
                Vec<AgentMissionReturn>,
            ) -> Result<MothershipDockCycle, String> = accept_hyper_agent_returns;

            let _inspector: fn(&FleetControllerSession) -> FleetInspectorSnapshot =
                inspector_snapshot;

            let _checkpoint: fn(&FleetControllerSession) -> FleetVspCheckpoint = checkpoint;

            let _resume: fn(&FleetVspCheckpoint, &FleetControllerSession) -> Result<(), String> =
                validate_resume;
        }
    }
}

pub use vertex_bridge_dock::{
    MOTHERSHIP_BRIDGE_SCHEMA, MothershipDockCycle, accept_hyper_agent_returns,
    checkpoint as create_bridge_checkpoint, inspector_snapshot as bridge_inspector_snapshot,
    validate_resume as validate_bridge_resume,
};

// ================================================================
// VERTEX MOTHERSHIP LIVE INGRESS V1
//
// Raw Genesis Wire V1 payloads arrive here.
//
// Binding authority:
//   execution_id -> current dispatch
//                -> mission
//                -> Hyper Agent identity
//
// The resulting trusted AgentMissionReturn set is then passed
// into the already verified Mothership Bridge Dock V1.
// ================================================================

pub mod live_wire_ingress {
    use crate::{MothershipDockCycle, accept_hyper_agent_returns};

    use vsa_vertex_bridge::{FleetControllerSession, genesis_wire_payloads_to_returns};

    pub const LIVE_WIRE_INGRESS_SCHEMA: &str = "vertex.mothership.live-ingress.v1";

    pub fn accept_live_genesis_wire_batch(
        session: &FleetControllerSession,
        payloads: Vec<String>,
    ) -> Result<MothershipDockCycle, String> {
        let returns = genesis_wire_payloads_to_returns(session, payloads)?;

        accept_hyper_agent_returns(session, returns)
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn live_wire_ingress_schema_is_locked() {
            assert_eq!(
                LIVE_WIRE_INGRESS_SCHEMA,
                "vertex.mothership.live-ingress.v1"
            );
        }

        #[test]
        fn live_wire_ingress_contract_is_callable() {
            let _entry: fn(
                &FleetControllerSession,
                Vec<String>,
            ) -> Result<MothershipDockCycle, String> = accept_live_genesis_wire_batch;
        }
    }
}

pub use live_wire_ingress::{LIVE_WIRE_INGRESS_SCHEMA, accept_live_genesis_wire_batch};

// ================================================================
// VERTEX MOTHERSHIP REAL AGENT RUNTIME V1
//
// Scheduler-owned execution specification
//      ↓
// std::process::Command
//      ↓
// machine stdout / stderr / exit status
//      ↓
// Genesis Wire V1
//      ↓
// Live Wire Ingress
//      ↓
// Dock / Lineage / Telemetry / VSP
//      ↓
// ARD Controller Advance
//      ↓
// NEXT WAVE
//
// No agent identity is accepted from the external process.
// Agent identity remains derived from the trusted dispatch.
// ================================================================

pub mod real_agent_runtime {
    use crate::{MothershipDockCycle, accept_live_genesis_wire_batch};

    use serde_json::json;

    use std::collections::HashMap;
    use std::process::Command;
    use std::time::Instant;

    use vsa_vertex_bridge::{FleetControllerSession, advance_controller_after_lineage_cycle};

    pub const REAL_AGENT_RUNTIME_SCHEMA: &str = "vertex.mothership.real-agent-runtime.v1";

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct RealAgentRunSpec {
        pub mission_id: String,
        pub program: String,
        pub args: Vec<String>,
        pub cwd: String,

        // Scheduler-owned runtime label.
        // Example:
        // RUN_BUILD / RUN_TEST / RUN_VVE
        pub capability: String,
    }

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct RealAgentProcessResult {
        pub mission_id: String,
        pub program: String,
        pub args: Vec<String>,
        pub cwd: String,
        pub capability: String,

        pub exit_code: Option<i32>,
        pub success: bool,

        pub stdout: String,
        pub stderr: String,

        pub duration_ms: u64,
    }

    #[derive(Debug)]
    pub struct MothershipIgnitionCycle {
        pub process_results: Vec<RealAgentProcessResult>,

        pub dock: MothershipDockCycle,

        pub advanced_session: FleetControllerSession,
    }

    pub fn execute_real_agent_process(
        spec: &RealAgentRunSpec,
    ) -> Result<RealAgentProcessResult, String> {
        if spec.program.trim().is_empty() {
            return Err("real agent process requires a program".into());
        }

        if spec.mission_id.trim().is_empty() {
            return Err("real agent process requires a mission id".into());
        }

        let started = Instant::now();

        let mut command = Command::new(&spec.program);

        command.args(&spec.args);

        if !spec.cwd.trim().is_empty() {
            command.current_dir(&spec.cwd);
        }

        let output = command.output().map_err(|error| {
            format!(
                "real agent process launch failed: mission={} program={} error={}",
                spec.mission_id, spec.program, error
            )
        })?;

        let duration_ms = started.elapsed().as_millis() as u64;

        Ok(RealAgentProcessResult {
            mission_id: spec.mission_id.clone(),

            program: spec.program.clone(),

            args: spec.args.clone(),

            cwd: spec.cwd.clone(),

            capability: spec.capability.clone(),

            exit_code: output.status.code(),

            success: output.status.success(),

            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),

            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),

            duration_ms,
        })
    }

    fn process_result_to_genesis_wire(
        execution_id: &str,
        result: &RealAgentProcessResult,
    ) -> String {
        let failed_missions = if result.success {
            Vec::<String>::new()
        } else {
            vec![result.mission_id.clone()]
        };

        json!({
            "schema":
                "vertex.genesis.observation.v1",

            "execution_id":
                execution_id,

            "mission_ids": [
                result.mission_id.clone()
            ],

            "runtime": [
                {
                    "mission_id":
                        result.mission_id.clone(),

                    "capability":
                        result.capability.clone(),

                    "run": {
                        "program":
                            result.program.clone(),

                        "args":
                            result.args.clone(),

                        "cwd":
                            result.cwd.clone(),

                        "exit_code":
                            result.exit_code
                                .map(i64::from),

                        "timed_out":
                            false,

                        "stdout_ref":
                            if result.stdout.is_empty() {
                                None::<String>
                            } else {
                                Some(
                                    result.stdout.clone()
                                )
                            },

                        "stderr_ref":
                            if result.stderr.is_empty() {
                                None::<String>
                            } else {
                                Some(
                                    result.stderr.clone()
                                )
                            }
                    }
                }
            ],

            "vve": [],

            "changed_files": [],

            "human_gate": {
                "required": false,
                "reasons": []
            },

            "failed_missions":
                failed_missions,

            "denied_missions": []
        })
        .to_string()
    }

    /// Main ignition entry.
    ///
    /// Runs every mission currently dispatched by the controller,
    /// emits one Genesis Wire payload per execution, docks them,
    /// generates lineage/telemetry/VSP state and advances ARD to
    /// the next Wave.
    pub fn ignite_current_wave(
        session: FleetControllerSession,
        runs: Vec<RealAgentRunSpec>,
    ) -> Result<MothershipIgnitionCycle, String> {
        let completed_dispatch = session
            .current_wave
            .dispatch
            .clone()
            .ok_or_else(|| "mothership ignition requires an active dispatch".to_string())?;

        if runs.len() != completed_dispatch.dispatches.len() {
            return Err(format!(
                "mothership ignition run count mismatch: expected={} actual={}",
                completed_dispatch.dispatches.len(),
                runs.len()
            ));
        }

        let mut runs_by_mission = HashMap::new();

        for run in runs {
            let mission_id = run.mission_id.clone();

            if runs_by_mission.insert(mission_id.clone(), run).is_some() {
                return Err(format!(
                    "duplicate real-agent run specification: {mission_id}"
                ));
            }
        }

        let mut process_results = Vec::with_capacity(completed_dispatch.dispatches.len());

        let mut payloads = Vec::with_capacity(completed_dispatch.dispatches.len());

        // Dispatch is the authority.
        //
        // User/process input cannot select execution_id
        // or Hyper Agent identity.
        for dispatch in &completed_dispatch.dispatches {
            let mission_id = dispatch.request.assignment.mission_id.clone();

            let run = runs_by_mission.get(&mission_id).ok_or_else(|| {
                format!("missing real-agent run for dispatched mission: {mission_id}")
            })?;

            let result = execute_real_agent_process(run)?;

            let payload = process_result_to_genesis_wire(&dispatch.execution_id, &result);

            process_results.push(result);
            payloads.push(payload);
        }

        // Existing Live Ingress performs:
        //
        // execution -> dispatch -> mission -> agent
        // binding and then invokes the verified Dock.
        let dock = accept_live_genesis_wire_batch(&session, payloads)?;

        // Existing Bridge controller code remains the authority
        // for ARD transition and next-wave scheduling.
        let advanced_session =
            advance_controller_after_lineage_cycle(session, &completed_dispatch, &dock.cycle)?;

        Ok(MothershipIgnitionCycle {
            process_results,
            dock,
            advanced_session,
        })
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[cfg(windows)]
        fn success_probe() -> RealAgentRunSpec {
            RealAgentRunSpec {
                mission_id: "mission-probe".into(),

                program: "cmd".into(),

                args: vec!["/C".into(), "echo VERTEX_REAL_AGENT_OK".into()],

                cwd: ".".into(),

                capability: "RUN_BUILD".into(),
            }
        }

        #[cfg(not(windows))]
        fn success_probe() -> RealAgentRunSpec {
            RealAgentRunSpec {
                mission_id: "mission-probe".into(),

                program: "sh".into(),

                args: vec!["-c".into(), "printf VERTEX_REAL_AGENT_OK".into()],

                cwd: ".".into(),

                capability: "RUN_BUILD".into(),
            }
        }

        #[cfg(windows)]
        fn failure_probe() -> RealAgentRunSpec {
            RealAgentRunSpec {
                mission_id: "mission-fail".into(),

                program: "cmd".into(),

                args: vec!["/C".into(), "exit /B 7".into()],

                cwd: ".".into(),

                capability: "RUN_TEST".into(),
            }
        }

        #[cfg(not(windows))]
        fn failure_probe() -> RealAgentRunSpec {
            RealAgentRunSpec {
                mission_id: "mission-fail".into(),

                program: "sh".into(),

                args: vec!["-c".into(), "exit 7".into()],

                cwd: ".".into(),

                capability: "RUN_TEST".into(),
            }
        }

        #[test]
        fn real_agent_runtime_schema_is_locked() {
            assert_eq!(
                REAL_AGENT_RUNTIME_SCHEMA,
                "vertex.mothership.real-agent-runtime.v1"
            );
        }

        #[test]
        fn real_agent_executes_actual_os_process() {
            let result =
                execute_real_agent_process(&success_probe()).expect("real process must execute");

            assert!(result.success);

            assert!(
                result.stdout.contains("VERTEX_REAL_AGENT_OK"),
                "actual stdout was not captured: {:?}",
                result.stdout
            );
        }

        #[test]
        fn real_agent_captures_machine_failure() {
            let result = execute_real_agent_process(&failure_probe())
                .expect("nonzero process is still an observable machine result");

            assert!(!result.success);

            assert_eq!(result.exit_code, Some(7));
        }

        #[test]
        fn actual_process_becomes_locked_genesis_wire() {
            let result = execute_real_agent_process(&success_probe()).unwrap();

            let payload = process_result_to_genesis_wire("execution-real-probe", &result);

            let wire = vsa_vertex_bridge::receive_genesis_observation_v1(&payload)
                .expect("real-process Genesis Wire must decode");

            assert_eq!(wire.execution_id, "execution-real-probe");

            assert_eq!(wire.mission_ids, vec!["mission-probe".to_string()]);

            let observations = vsa_vertex_bridge::genesis_wire_v1_to_observations(&wire)
                .expect("real-process Wire must normalize");

            assert_eq!(observations.len(), 1);

            assert_eq!(observations[0].runs.len(), 1);

            assert_eq!(observations[0].runs[0].exit_code, Some(0));
        }

        #[test]
        fn ignition_contract_is_callable() {
            let _entry: fn(
                FleetControllerSession,
                Vec<RealAgentRunSpec>,
            ) -> Result<MothershipIgnitionCycle, String> = ignite_current_wave;
        }
    }
}

pub use real_agent_runtime::{
    MothershipIgnitionCycle, REAL_AGENT_RUNTIME_SCHEMA, RealAgentProcessResult, RealAgentRunSpec,
    execute_real_agent_process, ignite_current_wave,
};

// ================================================================
// VERTEX MOTHERSHIP AUTONOMOUS MISSION LOOP V1
//
//                 MISSION
//                    |
//                    v
//              CURRENT WAVE
//                    |
//                    v
//            COMMAND RESOLVER
//                    |
//                    v
//             REAL OS PROCESS
//                    |
//                    v
//               GENESIS WIRE
//                    |
//                    v
//             MOTHERSHIP DOCK
//                    |
//                    v
//                  ARD
//                    |
//                    v
//             VSP CHECKPOINT
//                    |
//        +-----------+-----------+
//        |           |           |
//      Active    Completed     Stopped
//        |           |           |
//    NEXT WAVE    RETURN       HOLD
//        |
//        +---------- LOOP
//
// Design:
// - STEP API is suitable for GUI / Inspector control.
// - LOOP API is suitable for unattended Mothership execution.
// - Command resolution is separated from execution.
// - execution_id / Hyper Agent identity remain Dispatch-owned.
// - max_waves is a hard fail-closed infinite-loop guard.
// ================================================================

pub mod autonomous_mission_loop {
    use crate::{
        MothershipIgnitionCycle, RealAgentProcessResult, RealAgentRunSpec, ignite_current_wave,
    };

    use std::collections::HashMap;

    use vsa_vertex_bridge::{
        FleetControllerSession, FleetControllerSessionStatus, FleetVspCheckpoint,
    };

    pub const AUTONOMOUS_MISSION_SCHEMA: &str = "vertex.mothership.autonomous-mission.v1";

    // ------------------------------------------------------------
    // CONFIGURATION
    // ------------------------------------------------------------

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub struct AutonomousMissionConfig {
        /// Absolute safety ceiling.
        ///
        /// Even if a future scheduling bug leaves the controller
        /// permanently Active, the Mothership cannot spin forever.
        pub max_waves: usize,
    }

    impl Default for AutonomousMissionConfig {
        fn default() -> Self {
            Self { max_waves: 128 }
        }
    }

    fn validate_autonomous_config(config: AutonomousMissionConfig) -> Result<(), String> {
        if config.max_waves == 0 {
            return Err("autonomous mission max_waves must be greater than zero".into());
        }

        Ok(())
    }

    // ------------------------------------------------------------
    // CONTROL POLICY
    // ------------------------------------------------------------

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum AutonomousMissionLoopDecision {
        ContinueFlight,
        ReturnHome,
        HoldPosition,
    }

    pub fn autonomous_mission_loop_decision(
        status: FleetControllerSessionStatus,
    ) -> AutonomousMissionLoopDecision {
        match status {
            FleetControllerSessionStatus::Active => AutonomousMissionLoopDecision::ContinueFlight,

            FleetControllerSessionStatus::Completed => AutonomousMissionLoopDecision::ReturnHome,

            FleetControllerSessionStatus::Stopped => AutonomousMissionLoopDecision::HoldPosition,
        }
    }

    // ------------------------------------------------------------
    // COMMAND RESOLUTION
    //
    // The resolver decides WHAT real process belongs to each
    // dispatched Mission.
    //
    // It does NOT own:
    // - execution_id
    // - agent identity
    // - dispatch identity
    //
    // Those remain authoritative inside Bridge/Mothership.
    // ------------------------------------------------------------

    pub trait MissionRunResolver {
        fn resolve(
            &mut self,
            session: &FleetControllerSession,
        ) -> Result<Vec<RealAgentRunSpec>, String>;
    }

    /// Simple production-ready command catalog.
    ///
    /// Later the GUI, Hyper Agent planner, Model Router or VXN can
    /// implement MissionRunResolver dynamically without changing
    /// the autonomous flight engine.
    #[derive(Debug, Clone, Default)]
    pub struct MissionCommandCatalog {
        specs: HashMap<String, RealAgentRunSpec>,
    }

    impl MissionCommandCatalog {
        pub fn new() -> Self {
            Self::default()
        }

        pub fn len(&self) -> usize {
            self.specs.len()
        }

        pub fn is_empty(&self) -> bool {
            self.specs.is_empty()
        }

        pub fn insert(&mut self, spec: RealAgentRunSpec) -> Result<(), String> {
            let mission_id = spec.mission_id.trim();

            if mission_id.is_empty() {
                return Err("mission command catalog requires a mission id".into());
            }

            if self.specs.contains_key(mission_id) {
                return Err(format!(
                    "duplicate mission command catalog entry: {mission_id}"
                ));
            }

            self.specs.insert(mission_id.to_string(), spec);

            Ok(())
        }

        pub fn get(&self, mission_id: &str) -> Option<&RealAgentRunSpec> {
            self.specs.get(mission_id)
        }
    }

    impl MissionRunResolver for MissionCommandCatalog {
        fn resolve(
            &mut self,
            session: &FleetControllerSession,
        ) -> Result<Vec<RealAgentRunSpec>, String> {
            let dispatch = session
                .current_wave
                .dispatch
                .as_ref()
                .ok_or_else(|| "autonomous resolver requires an active dispatch".to_string())?;

            let mut runs = Vec::with_capacity(dispatch.dispatches.len());

            // Dispatch order is preserved exactly.
            //
            // This keeps the run batch deterministic and aligned
            // with the already verified Live Ingress boundary.
            for item in &dispatch.dispatches {
                let mission_id = item.request.assignment.mission_id.as_str();

                let spec = self.specs.get(mission_id).cloned().ok_or_else(|| {
                    format!("no real-agent command registered for dispatched mission: {mission_id}")
                })?;

                runs.push(spec);
            }

            Ok(runs)
        }
    }

    // ------------------------------------------------------------
    // GUI / INSPECTOR FRIENDLY RECORDS
    // ------------------------------------------------------------

    #[derive(Debug)]
    pub struct AutonomousWaveRecord {
        pub sequence: usize,

        pub session_id: String,
        pub wave_id: String,
        pub dispatch_id: String,

        pub mission_ids: Vec<String>,

        pub process_results: Vec<RealAgentProcessResult>,

        pub emitted_event_count: usize,

        /// Exact VSP boundary emitted by the Dock for this Wave.
        pub checkpoint: FleetVspCheckpoint,

        pub resulting_status: FleetControllerSessionStatus,
    }

    #[derive(Debug)]
    pub struct AutonomousMissionStep {
        pub record: AutonomousWaveRecord,

        pub session: FleetControllerSession,
    }

    #[derive(Debug)]
    pub struct AutonomousMissionReport {
        pub initial_session_id: String,

        pub waves: Vec<AutonomousWaveRecord>,

        pub final_session: FleetControllerSession,
    }

    impl AutonomousMissionReport {
        pub fn wave_count(&self) -> usize {
            self.waves.len()
        }

        pub fn terminal_status(&self) -> FleetControllerSessionStatus {
            self.final_session.status
        }
    }

    // ------------------------------------------------------------
    // STEP API
    //
    // GUI can call this once per Wave:
    //
    // [Run Wave]
    //     ↓
    // AutonomousMissionStep
    //     ↓
    // refresh Inspector / Timeline / VSP / Mission Graph
    // ------------------------------------------------------------

    pub fn run_autonomous_mission_step(
        session: FleetControllerSession,
        resolver: &mut dyn MissionRunResolver,
    ) -> Result<AutonomousMissionStep, String> {
        vertex_live_publish_preflight(&session);
        if session.status != FleetControllerSessionStatus::Active {
            return Err("autonomous mission step requires an Active controller session".into());
        }

        let dispatch = session
            .current_wave
            .dispatch
            .as_ref()
            .ok_or_else(|| "active autonomous controller has no dispatch".to_string())?;

        let session_id = session.session_id.clone();

        let wave_id = session.current_wave.wave_id.clone();

        let dispatch_id = dispatch.dispatch_id.clone();

        let mission_ids = dispatch
            .dispatches
            .iter()
            .map(|item| item.request.assignment.mission_id.clone())
            .collect::<Vec<_>>();

        let completed_before = session.completed_waves;

        // Resolver sees the authoritative current Session but
        // cannot modify it.
        let runs = resolver.resolve(&session)?;

        // This is the already verified Main Engine path:
        //
        // Real Process
        // -> Genesis
        // -> Live Wire
        // -> Dock
        // -> Anti-Replay
        // -> Lineage
        // -> Telemetry
        // -> VSP
        // -> ARD
        // -> Controller Advance
        let ignition = ignite_current_wave(session, runs)?;

        let MothershipIgnitionCycle {
            process_results,
            dock,
            advanced_session,
        } = ignition;

        let emitted_event_count = dock.events.len();

        let checkpoint = dock.checkpoint;

        let resulting_status = advanced_session.status;

        let record = AutonomousWaveRecord {
            sequence: completed_before + 1,

            session_id,
            wave_id,
            dispatch_id,
            mission_ids,

            process_results,

            emitted_event_count,

            checkpoint,

            resulting_status,
        };
        vertex_live_publish_postflight(&record, &record.checkpoint);

        Ok(AutonomousMissionStep {
            record,
            session: advanced_session,
        })
    }

    // ------------------------------------------------------------
    // FULL AUTONOMOUS LOOP
    //
    // Runs until:
    //
    // Completed -> successful return
    // Stopped   -> controlled hold
    //
    // Infrastructure / contract failures return Err.
    // max_waves prevents uncontrolled infinite execution.
    // ------------------------------------------------------------

    pub fn run_autonomous_mission_loop(
        mut session: FleetControllerSession,
        resolver: &mut dyn MissionRunResolver,
        config: AutonomousMissionConfig,
    ) -> Result<AutonomousMissionReport, String> {
        validate_autonomous_config(config)?;

        let initial_session_id = session.session_id.clone();

        let mut waves = Vec::new();

        loop {
            match autonomous_mission_loop_decision(session.status) {
                AutonomousMissionLoopDecision::ReturnHome
                | AutonomousMissionLoopDecision::HoldPosition => {
                    return Ok(AutonomousMissionReport {
                        initial_session_id,
                        waves,
                        final_session: session,
                    });
                }

                AutonomousMissionLoopDecision::ContinueFlight => {}
            }

            if waves.len() >= config.max_waves {
                return Err(format!(
                    "autonomous mission exceeded max_waves safety ceiling: {}",
                    config.max_waves
                ));
            }

            let step = run_autonomous_mission_step(session, resolver)?;

            session = step.session;

            waves.push(step.record);
        }
    }

    // ------------------------------------------------------------
    // CONTRACT / POLICY TESTS
    // ------------------------------------------------------------

    #[cfg(test)]
    mod tests {
        use super::*;

        fn sample_spec(mission_id: &str) -> RealAgentRunSpec {
            RealAgentRunSpec {
                mission_id: mission_id.into(),

                program: "vertex-test-process".into(),

                args: vec!["--probe".into()],

                cwd: ".".into(),

                capability: "RUN_BUILD".into(),
            }
        }

        #[test]
        fn autonomous_mission_schema_is_locked() {
            assert_eq!(
                AUTONOMOUS_MISSION_SCHEMA,
                "vertex.mothership.autonomous-mission.v1"
            );
        }

        #[test]
        fn autonomous_mission_zero_wave_budget_is_rejected() {
            let error = validate_autonomous_config(AutonomousMissionConfig { max_waves: 0 })
                .expect_err("zero wave budget must fail closed");

            assert!(error.contains("greater than zero"));
        }

        #[test]
        fn autonomous_mission_active_policy_continues_flight() {
            assert_eq!(
                autonomous_mission_loop_decision(FleetControllerSessionStatus::Active,),
                AutonomousMissionLoopDecision::ContinueFlight
            );
        }

        #[test]
        fn autonomous_mission_completed_policy_returns_home() {
            assert_eq!(
                autonomous_mission_loop_decision(FleetControllerSessionStatus::Completed,),
                AutonomousMissionLoopDecision::ReturnHome
            );
        }

        #[test]
        fn autonomous_mission_stopped_policy_holds_position() {
            assert_eq!(
                autonomous_mission_loop_decision(FleetControllerSessionStatus::Stopped,),
                AutonomousMissionLoopDecision::HoldPosition
            );
        }

        #[test]
        fn autonomous_mission_catalog_rejects_duplicate_mission() {
            let mut catalog = MissionCommandCatalog::new();

            catalog.insert(sample_spec("mission-build")).unwrap();

            let error = catalog
                .insert(sample_spec("mission-build"))
                .expect_err("duplicate catalog mission must fail");

            assert!(error.contains("duplicate mission command catalog entry"));
        }

        #[test]
        fn autonomous_mission_catalog_preserves_registered_command() {
            let mut catalog = MissionCommandCatalog::new();

            catalog.insert(sample_spec("mission-build")).unwrap();

            assert_eq!(catalog.len(), 1);

            assert_eq!(
                catalog.get("mission-build").unwrap().program,
                "vertex-test-process"
            );
        }

        #[test]
        fn autonomous_mission_step_contract_is_callable() {
            let _entry: fn(
                FleetControllerSession,
                &mut dyn MissionRunResolver,
            ) -> Result<AutonomousMissionStep, String> = run_autonomous_mission_step;
        }

        #[test]
        fn autonomous_mission_loop_contract_is_callable() {
            let _entry: fn(
                FleetControllerSession,
                &mut dyn MissionRunResolver,
                AutonomousMissionConfig,
            ) -> Result<AutonomousMissionReport, String> = run_autonomous_mission_loop;
        }
    }

    // VERTEX LIVE SESSION BUS V1
    fn vertex_live_json_escape(value: &str) -> String {
        let mut out = String::with_capacity(value.len() + 16);
        for ch in value.chars() {
            match ch {
                '"' => out.push_str("\\\""),
                '\\' => out.push_str("\\\\"),
                '\n' => out.push_str("\\n"),
                '\r' => out.push_str("\\r"),
                '\t' => out.push_str("\\t"),
                c if c.is_control() => out.push_str(&format!("\\u{:04x}", c as u32)),
                c => out.push(c),
            }
        }
        out
    }

    fn vertex_live_quote(value: &str) -> String {
        format!("\"{}\"", vertex_live_json_escape(value))
    }

    fn vertex_live_string_array(values: &[String]) -> String {
        let body = values
            .iter()
            .map(|value| vertex_live_quote(value))
            .collect::<Vec<_>>()
            .join(",");
        format!("[{}]", body)
    }

    fn vertex_live_runtime_dir() -> std::path::PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("_vertex_runtime")
    }

    fn vertex_live_publish_json(json: &str) {
        use std::io::Write;

        let dir = vertex_live_runtime_dir();
        if std::fs::create_dir_all(&dir).is_err() {
            return;
        }

        let latest = dir.join("live_session_latest.json");
        let temp = dir.join("live_session_latest.tmp");

        if std::fs::write(&temp, json.as_bytes()).is_ok() {
            let _ = std::fs::remove_file(&latest);
            let _ = std::fs::rename(&temp, &latest);
        }

        if let Ok(mut file) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(dir.join("live_session.ndjson"))
        {
            let _ = writeln!(file, "{}", json);
        }
    }

    fn vertex_live_publish_preflight(session: &FleetControllerSession) {
        let now_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis();

        let (dispatch_id, executions) = match session.current_wave.dispatch.as_ref() {
            Some(dispatch) => {
                let executions = dispatch
                    .dispatches
                    .iter()
                    .map(|execution| {
                        format!(
                            "{{\"execution_id\":{}}}",
                            vertex_live_quote(&execution.execution_id)
                        )
                    })
                    .collect::<Vec<_>>()
                    .join(",");

                (dispatch.dispatch_id.clone(), format!("[{}]", executions))
            }
            None => (String::new(), "[]".to_owned()),
        };

        let json = format!(
            "{{\"schema\":\"vertex.mothership.live-session.v1\",\"kind\":\"wave_scheduled\",\"timestamp_ms\":{},\"session\":{{\"session_id\":{},\"status\":{},\"completed_waves\":{}}},\"wave\":{{\"wave_id\":{},\"ready\":{},\"blocked\":{},\"waiting\":{}}},\"dispatch\":{{\"dispatch_id\":{},\"mission_set\":{},\"executions\":{}}},\"genesis\":{{\"event_count\":0}},\"vsp\":null}}",
            now_ms,
            vertex_live_quote(&session.session_id),
            vertex_live_quote(&format!("{:?}", session.status)),
            session.completed_waves,
            vertex_live_quote(&session.current_wave.wave_id),
            vertex_live_string_array(&session.current_wave.ready_mission_ids),
            vertex_live_string_array(&session.current_wave.blocked_mission_ids),
            vertex_live_string_array(&session.current_wave.waiting_mission_ids),
            vertex_live_quote(&dispatch_id),
            vertex_live_string_array(&session.current_wave.ready_mission_ids),
            executions
        );

        vertex_live_publish_json(&json);
    }

    fn vertex_live_publish_postflight<C: std::fmt::Debug>(
        record: &AutonomousWaveRecord,
        checkpoint: &C,
    ) {
        let now_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis();

        let json = format!(
            "{{\"schema\":\"vertex.mothership.live-session.v1\",\"kind\":\"wave_completed\",\"timestamp_ms\":{},\"session\":{{\"session_id\":{},\"status\":{},\"completed_waves\":{}}},\"wave\":{{\"sequence\":{},\"wave_id\":{},\"missions\":{},\"resulting_status\":{}}},\"dispatch\":{{\"dispatch_id\":{},\"confirmed_missions\":{},\"process_result_count\":{}}},\"genesis\":{{\"event_count\":{}}},\"vsp\":{{\"checkpoint_debug\":{}}}}}",
            now_ms,
            vertex_live_quote(&record.session_id),
            vertex_live_quote(&format!("{:?}", record.resulting_status)),
            record.sequence,
            record.sequence,
            vertex_live_quote(&record.wave_id),
            vertex_live_string_array(&record.mission_ids),
            vertex_live_quote(&format!("{:?}", record.resulting_status)),
            vertex_live_quote(&record.dispatch_id),
            vertex_live_string_array(&record.mission_ids),
            record.process_results.len(),
            record.emitted_event_count,
            vertex_live_quote(&format!("{:#?}", checkpoint))
        );

        vertex_live_publish_json(&json);
    }
    // END VERTEX LIVE SESSION BUS V1
}

pub use autonomous_mission_loop::{
    AUTONOMOUS_MISSION_SCHEMA, AutonomousMissionConfig, AutonomousMissionLoopDecision,
    AutonomousMissionReport, AutonomousMissionStep, AutonomousWaveRecord, MissionCommandCatalog,
    MissionRunResolver, autonomous_mission_loop_decision, run_autonomous_mission_loop,
    run_autonomous_mission_step,
};

pub mod real_hyper_agent_runtime;

pub use real_hyper_agent_runtime::{
    HyperAgentMission, HyperAgentProviderResult, HyperAgentWorkspace, HyperAgentWorkspaceWrite,
    OllamaProviderSpec, REAL_HYPER_AGENT_RUNTIME_SCHEMA, RealHyperAgentPipelineReport,
    execute_ollama_provider, execute_real_hyper_agent_pipeline, extract_hyper_agent_file,
};
