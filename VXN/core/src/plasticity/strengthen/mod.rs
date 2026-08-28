pub fn apply(value: f64, delta: f64) -> f64 {
    (value + delta).clamp(0.0, 1.0)
}
