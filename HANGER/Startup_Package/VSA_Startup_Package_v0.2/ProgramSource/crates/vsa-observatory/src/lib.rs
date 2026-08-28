use std::collections::HashMap;
use vsa_foundation::Id;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TelemetryResult {
    Pass,
    Fail,
    Blocked,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MissionTelemetry {
    pub mission_id: Id,
    pub worker: String,
    pub model: String,
    pub language: String,
    pub result: TelemetryResult,
    pub duration_ms: u64,
    pub prompt_units: u64,
    pub retries: u32,
    pub changed_files: Vec<String>,
    pub build_result: Option<String>,
    pub test_result: Option<String>,
    pub scope_violations: u32,
    pub human_interventions: u32,
    pub vram_mb: Option<u64>,
    pub blocker: Option<String>,
    pub evidence: Vec<String>,
}

impl MissionTelemetry {
    /// Compact machine acknowledgement. This is the default ARD return path.
    pub fn fast_ack(&self) -> String {
        format!(
            "{:?}|{}|changed={}|build={}|test={}|retry={}|scope={}",
            self.result,
            self.mission_id.0,
            self.changed_files.len(),
            self.build_result.as_deref().unwrap_or("NA"),
            self.test_result.as_deref().unwrap_or("NA"),
            self.retries,
            self.scope_violations
        )
    }

    pub fn requires_exception_report(&self) -> bool {
        self.result != TelemetryResult::Pass || self.scope_violations > 0 || self.blocker.is_some()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReportView {
    None,
    FastAck,
    Exception,
    HumanGate,
}

pub fn report_view(t: &MissionTelemetry, human_gate: bool) -> ReportView {
    if human_gate {
        ReportView::HumanGate
    } else if t.requires_exception_report() {
        ReportView::Exception
    } else {
        ReportView::FastAck
    }
}

#[derive(Debug, Default)]
pub struct Observatory {
    pub records: Vec<MissionTelemetry>,
}
impl Observatory {
    pub fn record(&mut self, m: MissionTelemetry) {
        self.records.push(m);
    }
    pub fn pass_rate_by_model(&self) -> HashMap<String, f64> {
        let mut t: HashMap<String, (u64, u64)> = HashMap::new();
        for r in &self.records {
            let e = t.entry(r.model.clone()).or_default();
            e.1 += 1;
            if r.result == TelemetryResult::Pass {
                e.0 += 1;
            }
        }
        t.into_iter()
            .map(|(k, (p, n))| (k, p as f64 / n as f64))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pass_uses_fast_ack() {
        let t = MissionTelemetry {
            mission_id: Id("m1".into()),
            worker: "w".into(),
            model: "2B".into(),
            language: "compact-en".into(),
            result: TelemetryResult::Pass,
            duration_ms: 10,
            prompt_units: 2,
            retries: 0,
            changed_files: vec![],
            build_result: Some("PASS".into()),
            test_result: None,
            scope_violations: 0,
            human_interventions: 0,
            vram_mb: None,
            blocker: None,
            evidence: vec![],
        };
        assert_eq!(report_view(&t, false), ReportView::FastAck);
        assert!(t.fast_ack().starts_with("Pass|m1|"));
    }
}
