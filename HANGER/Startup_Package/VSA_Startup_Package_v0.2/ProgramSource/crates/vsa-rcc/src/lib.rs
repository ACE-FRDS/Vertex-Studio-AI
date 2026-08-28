use std::collections::HashMap;
use vsa_foundation::{VsaError, VsaResult};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HardwareProfile {
    pub cpu_threads: u32,
    pub ram_gb: u32,
    pub vram_gb: u32,
    pub gpu_name: String,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RccPolicy {
    pub name: String,
    pub work_unit: String,
    pub max_parallel_workers: u32,
    pub verification: String,
    pub prefer_local: bool,
    pub model_residency: String,
}
pub fn recommend(profile: &HardwareProfile) -> RccPolicy {
    if profile.vram_gb <= 16 {
        RccPolicy {
            name: "Small Model Swarm".into(),
            work_unit: "ultra-small".into(),
            max_parallel_workers: 4,
            verification: "batched-low-risk".into(),
            prefer_local: true,
            model_residency: "prefer".into(),
        }
    } else {
        RccPolicy {
            name: "Balanced Heavy".into(),
            work_unit: "small".into(),
            max_parallel_workers: 8,
            verification: "adaptive".into(),
            prefer_local: true,
            model_residency: "adaptive".into(),
        }
    }
}
pub fn parse_simple(text: &str) -> VsaResult<RccPolicy> {
    let mut m = HashMap::new();
    for line in text
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
    {
        let (k, v) = line
            .split_once('=')
            .ok_or_else(|| VsaError::Invalid(line.into()))?;
        m.insert(k.trim(), v.trim());
    }
    Ok(RccPolicy {
        name: m.get("name").unwrap_or(&"Custom").to_string(),
        work_unit: m.get("work_unit").unwrap_or(&"small").to_string(),
        max_parallel_workers: m
            .get("max_parallel_workers")
            .unwrap_or(&"1")
            .parse()
            .unwrap_or(1),
        verification: m.get("verification").unwrap_or(&"adaptive").to_string(),
        prefer_local: m.get("prefer_local").unwrap_or(&"true") == &"true",
        model_residency: m.get("model_residency").unwrap_or(&"adaptive").to_string(),
    })
}
