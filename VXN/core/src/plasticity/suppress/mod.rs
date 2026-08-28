pub fn apply(value: f64, factor: f64) -> f64 {
    (value * factor).clamp(0.0, 1.0)
}
