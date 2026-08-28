use std::collections::HashMap;

#[derive(Default)]
pub struct CapabilityRegistry {
    pub capabilities: HashMap<String, String>,
}

#[derive(Default)]
pub struct ProviderRegistry {
    pub providers: HashMap<String, String>,
}
