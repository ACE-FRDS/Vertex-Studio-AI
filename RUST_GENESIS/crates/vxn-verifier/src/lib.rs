//! Vertex Fleet Genesis crate: vxn-verifier
#[derive(Debug,Clone,PartialEq,Eq)]
pub struct Capability { pub id: &'static str }
pub fn capability() -> Capability { Capability { id: "vxn-verifier" } }
#[cfg(test)] mod tests { use super::*; #[test] fn identity() { assert_eq!(capability().id,"vxn-verifier"); } }
