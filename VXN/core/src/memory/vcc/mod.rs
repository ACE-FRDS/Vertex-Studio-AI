#[derive(Debug, Clone)]
pub struct ContinuityRecord {
    pub record_id: String,
    pub why: String,
    pub decision: String,
    pub evidence_refs: Vec<String>,
}
