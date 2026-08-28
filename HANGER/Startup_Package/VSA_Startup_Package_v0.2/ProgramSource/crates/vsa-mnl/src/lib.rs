use vsa_ard::ExecutionContract;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HumanPrompt {
    pub language: String,
    pub original: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CanonicalMission {
    pub action: String,
    pub object: String,
    pub constraints: Vec<String>,
    pub worker_language: String,
    pub contract: ExecutionContract,
}

pub fn normalize(prompt: &HumanPrompt) -> CanonicalMission {
    // v0.1 deterministic reference normalizer.
    // Production MNL may use a model, dictionary or VXN semantic layer,
    // but the canonical output remains structured and provenance-preserving.
    let lower = prompt.original.to_lowercase();
    let action = if lower.contains("作") || lower.contains("create") {
        "create"
    } else if lower.contains("修") || lower.contains("fix") {
        "repair"
    } else if lower.contains("調") || lower.contains("inspect") {
        "inspect"
    } else {
        "execute"
    };
    CanonicalMission {
        action: action.into(),
        object: prompt.original.clone(),
        constraints: vec![
            "preserve human intent".into(),
            "current evidence over assumption".into(),
        ],
        worker_language: "compact-en".into(),
        contract: ExecutionContract {
            role: "Worker".into(),
            scope: vec![],
            forbidden: vec!["silent scope expansion".into()],
            stop_conditions: vec!["current reproducible blocker".into()],
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn preserves_original() {
        let h = HumanPrompt {
            language: "ja".into(),
            original: "静的ホームページを作る".into(),
        };
        let n = normalize(&h);
        assert_eq!(n.object, h.original);
        assert_eq!(n.action, "create");
    }
}
