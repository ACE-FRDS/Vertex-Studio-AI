use std::collections::{HashMap, HashSet, VecDeque};
use vsa_foundation::{Id, VsaError, VsaResult};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MissionState {
    Pending,
    Ready,
    Running,
    Pass,
    Fail,
    Blocked,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExecutionContract {
    pub role: String,
    pub scope: Vec<String>,
    pub forbidden: Vec<String>,
    pub stop_conditions: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkUnit {
    pub id: Id,
    pub parent: Option<Id>,
    pub title: String,
    pub depends_on: Vec<Id>,
    pub state: MissionState,
    pub contract: ExecutionContract,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Legacy compatibility footer. Telemetry-first ARD should populate this from system observation,
/// not require Workers to author narrative reports.
pub struct WorkerFooter {
    pub result: MissionState,
    pub evidence: Vec<String>,
    pub changed_files: Vec<String>,
    pub current_blocker: Option<String>,
    pub scope_violation: bool,
    pub unplanned_exploration: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReportingPolicy {
    TelemetryOnly,
    ExceptionOnly,
    HumanGate,
}

pub fn default_reporting_policy(state: MissionState, human_gate: bool) -> ReportingPolicy {
    if human_gate {
        ReportingPolicy::HumanGate
    } else if matches!(
        state,
        MissionState::Fail | MissionState::Blocked | MissionState::Unknown
    ) {
        ReportingPolicy::ExceptionOnly
    } else {
        ReportingPolicy::TelemetryOnly
    }
}

#[derive(Debug, Default)]
pub struct MissionGraph {
    pub units: HashMap<Id, WorkUnit>,
}

impl MissionGraph {
    pub fn add(&mut self, unit: WorkUnit) -> VsaResult<()> {
        if self.units.contains_key(&unit.id) {
            return Err(VsaError::Conflict(unit.id.0));
        }
        self.units.insert(unit.id.clone(), unit);
        Ok(())
    }

    pub fn refresh_ready(&mut self) {
        let passed: HashSet<Id> = self
            .units
            .values()
            .filter(|u| u.state == MissionState::Pass)
            .map(|u| u.id.clone())
            .collect();
        for u in self.units.values_mut() {
            if u.state == MissionState::Pending && u.depends_on.iter().all(|d| passed.contains(d)) {
                u.state = MissionState::Ready;
            }
        }
    }

    pub fn ready_queue(&self) -> VecDeque<Id> {
        let mut ids: Vec<_> = self
            .units
            .values()
            .filter(|u| u.state == MissionState::Ready)
            .map(|u| u.id.clone())
            .collect();
        ids.sort();
        ids.into()
    }

    pub fn apply_footer(&mut self, id: &Id, footer: WorkerFooter) -> VsaResult<()> {
        let u = self
            .units
            .get_mut(id)
            .ok_or_else(|| VsaError::NotFound(id.0.clone()))?;
        u.state = footer.result;
        Ok(())
    }
}

pub fn ultra_fine_decompose(title: &str, steps: &[&str]) -> Vec<WorkUnit> {
    let parent = Id::new("mission");
    steps
        .iter()
        .enumerate()
        .map(|(i, s)| WorkUnit {
            id: Id(format!("{}-{}", parent.0, i + 1)),
            parent: Some(parent.clone()),
            title: format!("{title}: {s}"),
            depends_on: if i == 0 {
                vec![]
            } else {
                vec![Id(format!("{}-{}", parent.0, i))]
            },
            state: MissionState::Pending,
            contract: ExecutionContract {
                role: "Local Developer".into(),
                scope: vec![],
                forbidden: vec![],
                stop_conditions: vec!["current reproducible blocker".into()],
            },
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dependency_makes_next_ready() {
        let units = ultra_fine_decompose("x", &["a", "b"]);
        let mut g = MissionGraph::default();
        for u in units {
            g.add(u).unwrap();
        }
        g.refresh_ready();
        let first = g.ready_queue().pop_front().unwrap();
        g.units.get_mut(&first).unwrap().state = MissionState::Pass;
        g.refresh_ready();
        assert_eq!(g.ready_queue().len(), 1);
    }
}
