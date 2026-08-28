#[derive(Debug, Clone, Copy)]
pub enum Residency {
    Hot,
    Warm,
    Cold,
    Remote,
}

#[derive(Debug, Clone)]
pub struct ModelResidency {
    pub model_id: String,
    pub residency: Residency,
    pub vram_estimate_bytes: u64,
}
