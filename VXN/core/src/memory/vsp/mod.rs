#[derive(Debug, Clone)]
pub struct SavePoint {
    pub save_point_id: String,
    pub canonical_revision: String,
    pub mission_id: Option<String>,
    pub created_at: String,
}
