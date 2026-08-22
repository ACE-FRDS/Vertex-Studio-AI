//! Vertex Fleet Genesis crate: frontier-core
#[derive(Debug,Clone,PartialEq,Eq)]
pub struct Capability { pub id: &'static str }
pub fn capability() -> Capability { Capability { id: "frontier-core" } }
#[cfg(test)] mod tests { use super::*; #[test] fn identity() { assert_eq!(capability().id,"frontier-core"); } }
