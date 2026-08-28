use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub enum ModelTier {
    Deterministic = 0,
    Small3B4B = 1,
    Medium8B = 2,
    Medium12B = 3,
    Large30B = 4,
    CloudLarge = 5,
    Human = 6,
}

impl ModelTier {
    pub fn shift(self, delta: i32) -> Self {
        let raw = (self as i32 + delta).clamp(0, 6);
        match raw {
            0 => ModelTier::Deterministic,
            1 => ModelTier::Small3B4B,
            2 => ModelTier::Medium8B,
            3 => ModelTier::Medium12B,
            4 => ModelTier::Large30B,
            5 => ModelTier::CloudLarge,
            _ => ModelTier::Human,
        }
    }
}
