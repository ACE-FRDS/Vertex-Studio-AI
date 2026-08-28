#[derive(Debug, Clone)]
pub struct WorkingMemoryItem {
    pub key: String,
    pub value_ref: String,
    pub activation: f32,
}
