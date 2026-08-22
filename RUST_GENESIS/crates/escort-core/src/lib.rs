//! Vertex Fleet Genesis crate: escort-core
#[derive(Debug,Clone,PartialEq,Eq)]
pub struct Capability { pub id: &'static str }
pub fn capability() -> Capability { Capability { id: "escort-core" } }
#[cfg(test)] mod tests { use super::*; #[test] fn identity() { assert_eq!(capability().id,"escort-core"); } }
