#[derive(Debug, Clone)]
pub struct ModelDialectProfile {
    pub model_id: String,
    pub natural_language: f32,
    pub structured_text: f32,
    pub json: f32,
    pub compact_vxn: f32,
    pub native_vxn: f32,
}
