#[derive(Debug, Clone)]
pub struct ImpactValue {
    pub value: f64,
    pub protected: bool,
}

impl ImpactValue {
    pub fn clamp(&mut self) {
        self.value = self.value.clamp(0.0, 1.0);
    }
}

// IMPORTANT: Impact is attention pressure, not truth confidence.
