use serde_json::Value;
use std::collections::HashMap;
use vertex_core::{MissionEnvelope, MissionState};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ObservedMissionState {
    Accepted,
    Completed,
    Denied,
    Failed,
    HumanGateRequired,
}

impl From<&MissionState> for ObservedMissionState {
    fn from(state: &MissionState) -> Self {
        match state {
            MissionState::Accepted => Self::Accepted,
            MissionState::Completed => Self::Completed,
            MissionState::Denied => Self::Denied,
            MissionState::Failed => Self::Failed,
            MissionState::HumanGateRequired => Self::HumanGateRequired,
        }
    }
}

/// Stable observation boundary above Genesis Harness.
///
/// This intentionally preserves the Harness result as machine-produced JSON.
/// Specialized Runtime/VVE extraction is layered on top of this type.
#[derive(Debug, Clone, PartialEq)]
pub struct GenesisMissionObservation {
    pub mission_id: String,
    pub actor: String,
    pub capability: String,
    pub state: ObservedMissionState,
    pub result: Option<Value>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeObservation {
    pub program: String,
    pub args: Vec<String>,
    pub cwd: String,
    pub exit_code: Option<i64>,
    pub timed_out: bool,
    pub stdout: Option<String>,
    pub stderr: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VveFileObservation {
    pub path: String,
    pub bytes: u64,
    pub sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VveObservation {
    pub changeset_id: String,
    pub state: String,
    pub files: Vec<VveFileObservation>,
}

pub fn extract_runtime(observation: &GenesisMissionObservation) -> Option<RuntimeObservation> {
    if observation.capability != "RUN_BUILD" && observation.capability != "RUN_TEST" {
        return None;
    }

    let result = observation.result.as_ref()?;

    Some(RuntimeObservation {
        program: result.get("program")?.as_str()?.to_owned(),
        args: result
            .get("args")?
            .as_array()?
            .iter()
            .map(|arg| arg.as_str().map(str::to_owned))
            .collect::<Option<Vec<_>>>()?,
        cwd: result.get("cwd")?.as_str()?.to_owned(),
        exit_code: result.get("exit_code").and_then(Value::as_i64),
        timed_out: result
            .get("timed_out")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        stdout: result
            .get("stdout")
            .and_then(Value::as_str)
            .map(str::to_owned),
        stderr: result
            .get("stderr")
            .and_then(Value::as_str)
            .map(str::to_owned),
    })
}

pub fn extract_vve(observation: &GenesisMissionObservation) -> Option<VveObservation> {
    if observation.capability != "CREATE_VVE_CHANGESET"
        && observation.capability != "WRITE_VVE_FILE"
    {
        return None;
    }

    let result = observation.result.as_ref()?;

    let changeset_id = result.get("changeset_id")?.as_str()?.to_owned();
    let state = result.get("state")?.as_str()?.to_owned();

    let files = result
        .get("files")?
        .as_array()?
        .iter()
        .filter_map(|file| {
            Some(VveFileObservation {
                path: file.get("path")?.as_str()?.to_owned(),
                bytes: file.get("bytes")?.as_u64()?,
                sha256: file.get("sha256")?.as_str()?.to_owned(),
            })
        })
        .collect();

    Some(VveObservation {
        changeset_id,
        state,
        files,
    })
}

pub fn human_gate_reason(observation: &GenesisMissionObservation) -> Option<&str> {
    if observation.state != ObservedMissionState::HumanGateRequired {
        return None;
    }

    observation.result.as_ref()?.get("error")?.as_str()
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CollectedRuntimeObservation {
    pub mission_id: String,
    pub capability: String,
    pub runtime: RuntimeObservation,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CollectedVveObservation {
    pub mission_id: String,
    pub capability: String,
    pub changeset_id: String,
    pub state: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CollectedExecutionObservation {
    pub execution_id: String,

    pub mission_ids: Vec<String>,

    pub runtime: Vec<CollectedRuntimeObservation>,
    pub vve: Vec<CollectedVveObservation>,

    pub changed_files: Vec<VveFileObservation>,

    pub human_gate_required: bool,
    pub human_gate_reasons: Vec<String>,

    pub failed_missions: Vec<String>,
    pub denied_missions: Vec<String>,
}

#[derive(Debug)]
pub struct ExecutionObservationCollector {
    execution_id: String,
    observations: Vec<GenesisMissionObservation>,
}

impl ExecutionObservationCollector {
    pub fn new(execution_id: impl Into<String>) -> Self {
        Self {
            execution_id: execution_id.into(),
            observations: Vec::new(),
        }
    }

    pub fn push(&mut self, observation: GenesisMissionObservation) {
        self.observations.push(observation);
    }

    pub fn collect(self) -> CollectedExecutionObservation {
        let mut mission_ids = Vec::new();
        let mut runtime = Vec::new();
        let mut vve = Vec::new();

        let mut changed_files: HashMap<(String, String), VveFileObservation> = HashMap::new();

        let mut human_gate_required = false;
        let mut human_gate_reasons = Vec::new();

        let mut failed_missions = Vec::new();
        let mut denied_missions = Vec::new();

        for observation in self.observations {
            mission_ids.push(observation.mission_id.clone());

            match observation.state {
                ObservedMissionState::HumanGateRequired => {
                    human_gate_required = true;

                    if let Some(reason) = human_gate_reason(&observation) {
                        human_gate_reasons.push(reason.to_owned());
                    }
                }
                ObservedMissionState::Failed => {
                    failed_missions.push(observation.mission_id.clone());
                }
                ObservedMissionState::Denied => {
                    denied_missions.push(observation.mission_id.clone());
                }
                ObservedMissionState::Accepted | ObservedMissionState::Completed => {}
            }

            if let Some(runtime_observation) = extract_runtime(&observation) {
                runtime.push(CollectedRuntimeObservation {
                    mission_id: observation.mission_id.clone(),
                    capability: observation.capability.clone(),
                    runtime: runtime_observation,
                });
            }

            if let Some(vve_observation) = extract_vve(&observation) {
                vve.push(CollectedVveObservation {
                    mission_id: observation.mission_id.clone(),
                    capability: observation.capability.clone(),
                    changeset_id: vve_observation.changeset_id.clone(),
                    state: vve_observation.state.clone(),
                });

                for file in vve_observation.files {
                    changed_files.insert((file.path.clone(), file.sha256.clone()), file);
                }
            }
        }

        let mut changed_files: Vec<_> = changed_files.into_values().collect();

        changed_files.sort_by(|a, b| a.path.cmp(&b.path).then_with(|| a.sha256.cmp(&b.sha256)));

        mission_ids.sort();
        mission_ids.dedup();

        human_gate_reasons.sort();
        human_gate_reasons.dedup();

        failed_missions.sort();
        failed_missions.dedup();

        denied_missions.sort();
        denied_missions.dedup();

        CollectedExecutionObservation {
            execution_id: self.execution_id,
            mission_ids,
            runtime,
            vve,
            changed_files,
            human_gate_required,
            human_gate_reasons,
            failed_missions,
            denied_missions,
        }
    }
}
/// Stable JSON wire contract for exporting one collected Genesis execution.
///
/// This boundary intentionally does not serialize Genesis internal DTOs
/// directly. The explicit JSON shape can evolve independently from the
/// collector implementation.
pub fn collected_observation_to_wire_v1(observation: &CollectedExecutionObservation) -> Value {
    let runtime = observation
        .runtime
        .iter()
        .map(|item| {
            serde_json::json!({
                "mission_id": item.mission_id,
                "capability": item.capability,
                "run": {
                    "program": item.runtime.program,
                    "args": item.runtime.args,
                    "cwd": item.runtime.cwd,
                    "exit_code": item.runtime.exit_code,
                    "timed_out": item.runtime.timed_out,
                    "stdout_ref": item.runtime.stdout,
                    "stderr_ref": item.runtime.stderr,
                }
            })
        })
        .collect::<Vec<_>>();

    let vve = observation
        .vve
        .iter()
        .map(|item| {
            serde_json::json!({
                "mission_id": item.mission_id,
                "capability": item.capability,
                "changeset_id": item.changeset_id,
                "state": item.state,
            })
        })
        .collect::<Vec<_>>();

    let changed_files = observation
        .changed_files
        .iter()
        .map(|file| {
            serde_json::json!({
                "path": file.path,
                "bytes": file.bytes,
                "sha256": file.sha256,
            })
        })
        .collect::<Vec<_>>();

    serde_json::json!({
        "schema": "vertex.genesis.observation.v1",
        "execution_id": observation.execution_id,
        "mission_ids": observation.mission_ids,
        "runtime": runtime,
        "vve": vve,
        "changed_files": changed_files,
        "human_gate": {
            "required": observation.human_gate_required,
            "reasons": observation.human_gate_reasons,
        },
        "failed_missions": observation.failed_missions,
        "denied_missions": observation.denied_missions,
    })
}

pub fn collected_observation_to_wire_v1_json(
    observation: &CollectedExecutionObservation,
) -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(&collected_observation_to_wire_v1(observation))
}
pub fn observe_mission(envelope: &MissionEnvelope) -> GenesisMissionObservation {
    GenesisMissionObservation {
        mission_id: envelope.mission_id.clone(),
        actor: envelope.actor.clone(),
        capability: envelope.capability.as_str().to_string(),
        state: ObservedMissionState::from(&envelope.state),
        result: envelope.result.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use vertex_core::{Capability, MissionRequest};

    fn envelope(capability: Capability) -> MissionEnvelope {
        MissionEnvelope::new(MissionRequest {
            capability,
            payload: json!({}),
            actor: Some("Hyper Agent".into()),
        })
    }

    #[test]
    fn observes_real_genesis_mission_envelope() {
        let mut mission = envelope(Capability::RunBuild);

        mission.state = MissionState::Completed;
        mission.result = Some(json!({
            "exit_code": 0,
            "stdout": "build complete",
            "stderr": "",
            "timed_out": false
        }));

        let observation = observe_mission(&mission);

        assert_eq!(observation.mission_id, mission.mission_id);
        assert_eq!(observation.actor, "Hyper Agent");
        assert_eq!(observation.capability, "RUN_BUILD");
        assert_eq!(observation.state, ObservedMissionState::Completed);
        assert_eq!(
            observation
                .result
                .as_ref()
                .and_then(|value| value.get("exit_code"))
                .and_then(Value::as_i64),
            Some(0)
        );
    }

    #[test]
    fn extracts_runtime_machine_observation() {
        let mut mission = envelope(Capability::RunBuild);

        mission.state = MissionState::Completed;
        mission.result = Some(json!({
            "program": "cargo",
            "args": ["build", "--workspace"],
            "cwd": "G:\\Vertex_Project\\Fixture",
            "exit_code": 0,
            "stdout": "build complete",
            "stderr": "",
            "timed_out": false
        }));

        let observation = observe_mission(&mission);
        let runtime = extract_runtime(&observation).unwrap();

        assert_eq!(runtime.program, "cargo");
        assert_eq!(runtime.args, vec!["build", "--workspace"]);
        assert_eq!(runtime.cwd, "G:\\Vertex_Project\\Fixture");
        assert_eq!(runtime.exit_code, Some(0));
        assert!(!runtime.timed_out);
        assert_eq!(runtime.stdout.as_deref(), Some("build complete"));
        assert_eq!(runtime.stderr.as_deref(), Some(""));
    }

    #[test]
    fn extracts_real_vve_changeset_shape() {
        let mut mission = envelope(Capability::WriteVveFile);

        mission.state = MissionState::Completed;
        mission.result = Some(json!({
            "changeset_id": "changeset://vertex/abc",
            "created_at": "2026-08-23T00:00:00Z",
            "state": "DRAFT",
            "overlay_root": "G:\\VVE\\changesets\\abc",
            "files": [
                {
                    "path": "src/lib.rs",
                    "bytes": 128,
                    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                }
            ]
        }));

        let observation = observe_mission(&mission);
        let vve = extract_vve(&observation).unwrap();

        assert_eq!(vve.changeset_id, "changeset://vertex/abc");
        assert_eq!(vve.state, "DRAFT");
        assert_eq!(vve.files.len(), 1);
        assert_eq!(vve.files[0].path, "src/lib.rs");
        assert_eq!(vve.files[0].bytes, 128);
        assert_eq!(
            vve.files[0].sha256,
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        );
    }

    #[test]
    fn extracts_human_gate_reason() {
        let mut mission = envelope(Capability::PromoteVve);

        mission.state = MissionState::HumanGateRequired;
        mission.result = Some(json!({
            "error": "PROMOTE_VVE requires owner approval"
        }));

        let observation = observe_mission(&mission);

        assert_eq!(
            human_gate_reason(&observation),
            Some("PROMOTE_VVE requires owner approval")
        );
    }
    #[test]
    fn collector_combines_build_test_and_vve() {
        let mut build = envelope(Capability::RunBuild);
        build.state = MissionState::Completed;
        build.result = Some(json!({
            "program": "cargo",
            "args": ["build", "--workspace"],
            "cwd": "G:\\Vertex_Project\\Fixture",
            "exit_code": 0,
            "stdout": "build ok",
            "stderr": "",
            "timed_out": false
        }));

        let mut test = envelope(Capability::RunTest);
        test.state = MissionState::Completed;
        test.result = Some(json!({
            "program": "cargo",
            "args": ["test", "--workspace"],
            "cwd": "G:\\Vertex_Project\\Fixture",
            "exit_code": 0,
            "stdout": "tests ok",
            "stderr": "",
            "timed_out": false
        }));

        let mut vve = envelope(Capability::WriteVveFile);
        vve.state = MissionState::Completed;
        vve.result = Some(json!({
            "changeset_id": "changeset://vertex/abc",
            "created_at": "2026-08-23T00:00:00Z",
            "state": "DRAFT",
            "overlay_root": "G:\\VVE\\changesets\\abc",
            "files": [
                {
                    "path": "src/lib.rs",
                    "bytes": 128,
                    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                }
            ]
        }));

        let mut collector = ExecutionObservationCollector::new("ard-workunit-1");

        collector.push(observe_mission(&build));
        collector.push(observe_mission(&test));
        collector.push(observe_mission(&vve));

        let collected = collector.collect();

        assert_eq!(collected.execution_id, "ard-workunit-1");
        assert_eq!(collected.runtime.len(), 2);
        assert_eq!(collected.vve.len(), 1);
        assert_eq!(collected.changed_files.len(), 1);
        assert!(!collected.human_gate_required);
        assert!(collected.failed_missions.is_empty());
        assert!(collected.denied_missions.is_empty());
    }

    #[test]
    fn wire_v1_preserves_execution_runtime_and_evidence_contract() {
        let mut build = envelope(Capability::RunBuild);
        build.state = MissionState::Completed;

        build.result = Some(json!({
            "program": "cargo",
            "args": ["build", "--workspace"],
            "cwd": "G:\\Vertex_Project\\Fixture",
            "exit_code": 0,
            "stdout": "build ok",
            "stderr": "",
            "timed_out": false
        }));

        let mut test = envelope(Capability::RunTest);
        test.state = MissionState::Completed;

        test.result = Some(json!({
            "program": "cargo",
            "args": ["test", "--workspace"],
            "cwd": "G:\\Vertex_Project\\Fixture",
            "exit_code": 0,
            "stdout": "tests ok",
            "stderr": "",
            "timed_out": false
        }));

        let mut collector = ExecutionObservationCollector::new("execution-wire-v1");

        collector.push(observe_mission(&build));
        collector.push(observe_mission(&test));

        let collected = collector.collect();

        let wire = collected_observation_to_wire_v1(&collected);

        assert_eq!(wire["schema"], json!("vertex.genesis.observation.v1"));

        assert_eq!(wire["execution_id"], json!("execution-wire-v1"));

        assert_eq!(wire["runtime"].as_array().unwrap().len(), 2);

        assert_eq!(wire["runtime"][0]["run"]["program"], json!("cargo"));

        assert_eq!(
            wire["runtime"][0]["run"]["args"],
            json!(["build", "--workspace"])
        );

        assert_eq!(
            wire["runtime"][0]["run"]["cwd"],
            json!("G:\\Vertex_Project\\Fixture")
        );

        assert_eq!(wire["runtime"][0]["run"]["exit_code"], json!(0));

        assert_eq!(wire["runtime"][0]["run"]["timed_out"], json!(false));

        assert_eq!(wire["runtime"][0]["run"]["stdout_ref"], json!("build ok"));

        assert_eq!(
            wire["runtime"][1]["run"]["args"],
            json!(["test", "--workspace"])
        );

        assert_eq!(wire["human_gate"]["required"], json!(false));

        assert_eq!(wire["failed_missions"], json!([]));

        assert_eq!(wire["denied_missions"], json!([]));

        let encoded = collected_observation_to_wire_v1_json(&collected).unwrap();

        let decoded: Value = serde_json::from_str(&encoded).unwrap();

        assert_eq!(decoded, wire);
    }
    #[test]
    fn collector_deduplicates_same_file_evidence() {
        let file = json!({
            "path": "src/lib.rs",
            "bytes": 128,
            "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        });

        let mut first = envelope(Capability::WriteVveFile);
        first.state = MissionState::Completed;
        first.result = Some(json!({
            "changeset_id": "changeset://vertex/one",
            "created_at": "2026-08-23T00:00:00Z",
            "state": "DRAFT",
            "overlay_root": "G:\\VVE\\changesets\\one",
            "files": [file.clone()]
        }));

        let mut second = envelope(Capability::WriteVveFile);
        second.state = MissionState::Completed;
        second.result = Some(json!({
            "changeset_id": "changeset://vertex/two",
            "created_at": "2026-08-23T00:00:01Z",
            "state": "DRAFT",
            "overlay_root": "G:\\VVE\\changesets\\two",
            "files": [file]
        }));

        let mut collector = ExecutionObservationCollector::new("ard-workunit-2");

        collector.push(observe_mission(&first));
        collector.push(observe_mission(&second));

        let collected = collector.collect();

        assert_eq!(collected.vve.len(), 2);
        assert_eq!(collected.changed_files.len(), 1);
    }

    #[test]
    fn collector_preserves_human_gate_and_failures() {
        let mut gate = envelope(Capability::PromoteVve);
        gate.state = MissionState::HumanGateRequired;
        gate.result = Some(json!({
            "error": "owner approval required"
        }));

        let mut failed = envelope(Capability::RunTest);
        failed.state = MissionState::Failed;
        failed.result = Some(json!({
            "error": "test execution failed"
        }));

        let mut collector = ExecutionObservationCollector::new("ard-workunit-3");

        collector.push(observe_mission(&gate));
        collector.push(observe_mission(&failed));

        let collected = collector.collect();

        assert!(collected.human_gate_required);
        assert_eq!(
            collected.human_gate_reasons,
            vec!["owner approval required"]
        );
        assert_eq!(collected.failed_missions.len(), 1);
    }
    #[test]
    fn preserves_human_gate_state() {
        let mut mission = envelope(Capability::PromoteVve);

        mission.state = MissionState::HumanGateRequired;
        mission.result = Some(json!({
            "error": "owner approval required"
        }));

        let observation = observe_mission(&mission);

        assert_eq!(observation.state, ObservedMissionState::HumanGateRequired);
        assert_eq!(observation.capability, "PROMOTE_VVE");
        assert!(observation
            .result
            .as_ref()
            .and_then(|value| value.get("error"))
            .is_some());
    }
}
