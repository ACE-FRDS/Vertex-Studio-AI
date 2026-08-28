use vsa_foundation::Id;
#[derive(Debug,Clone,Copy,PartialEq,Eq)]
pub enum Relation { Merge, Adopt, Supersede, Share, Isolate, Migrate, Preserve }
#[derive(Debug,Clone,PartialEq,Eq)]
pub struct LineageNode { pub id:Id,pub name:String,pub source_repo:String,pub immutable_original:bool }
#[derive(Debug,Clone,PartialEq,Eq)]
pub struct ConvergenceEdge { pub from:Id,pub to:Id,pub relation:Relation,pub reason:String }
#[derive(Debug,Clone,Copy,PartialEq,Eq)]
pub enum Strategy { AAsBase, BAsBase, NeutralProject }
#[derive(Debug,Clone,Default)]
pub struct Blueprint { pub nodes:Vec<LineageNode>,pub edges:Vec<ConvergenceEdge> }
