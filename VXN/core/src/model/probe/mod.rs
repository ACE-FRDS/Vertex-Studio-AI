#[derive(Debug, Clone)]
pub struct CapabilityProbeResult {
    pub typed_structure: f32,
    pub id_preservation: f32,
    pub schema_following: f32,
    pub compact_notation: f32,
    pub tool_contract: f32,
    pub unknown_syntax_tolerance: f32,
}
