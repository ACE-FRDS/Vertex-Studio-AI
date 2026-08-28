#[derive(Debug, Clone, Default)]
pub struct ResourceState {
    pub cpu_percent: f32,
    pub ram_used_bytes: u64,
    pub ram_total_bytes: u64,
    pub vram_used_bytes: u64,
    pub vram_total_bytes: u64,
}
