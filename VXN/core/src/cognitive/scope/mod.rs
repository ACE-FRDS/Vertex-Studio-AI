#[derive(Debug, Clone)]
pub struct Scope {
    pub read_allow: Vec<String>,
    pub write_allow: Vec<String>,
    pub deny: Vec<String>,
}
