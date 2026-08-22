//! Vertex Fleet Genesis crate: hyper-agent-core
#[derive(Debug,Clone,PartialEq,Eq)]
pub struct Capability { pub id: &'static str }
pub fn capability() -> Capability { Capability { id: "hyper-agent-core" } }
#[cfg(test)] mod tests { use super::*; #[test] fn identity() { assert_eq!(capability().id,"hyper-agent-core"); } }
