#[derive(Debug, Clone)]
pub struct Uncertainty {
    pub confidence: f32,
    pub ambiguity: f32,
    pub novelty: f32,
    pub risk: f32,
}
