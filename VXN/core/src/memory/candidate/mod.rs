#[derive(Debug, Clone)]
pub struct CandidateWorld {
    pub candidate_id: String,
    pub parent_canonical_id: String,
    pub mutation_refs: Vec<String>,
}
