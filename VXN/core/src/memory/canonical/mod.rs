#[derive(Debug, Clone)]
pub struct CanonicalWorld {
    pub canonical_id: String,
    pub evidence_refs: Vec<String>,
    pub lineage_ref: Option<String>,
}
