use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum ToolboxComponent {
    Raw,
    LockScope,
    ImpactAssociation,
    VccVsp,
    Rag,
    CandidateVtc,
    Custom(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeToolbox {
    pub components: Vec<ToolboxComponent>,
    pub hot_swap_enabled: bool,
}

impl RuntimeToolbox {
    pub fn minimal() -> Self {
        Self {
            components: vec![ToolboxComponent::Raw],
            hot_swap_enabled: true,
        }
    }

    pub fn contains(&self, component: &ToolboxComponent) -> bool {
        self.components.contains(component)
    }

    pub fn attach(&mut self, component: ToolboxComponent) {
        if !self.components.contains(&component) {
            self.components.push(component);
        }
    }

    pub fn detach(&mut self, component: &ToolboxComponent) {
        self.components.retain(|x| x != component);
    }
}
