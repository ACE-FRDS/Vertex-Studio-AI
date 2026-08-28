use std::sync::{Arc,Mutex}; use std::time::SystemTime;
#[derive(Debug,Clone,PartialEq,Eq)] pub enum EventKind{ValidationPassed,OptimizationCompleted,ExecutionStarted,InstructionExecuted,ExecutionCompleted,CapabilityActivated}
#[derive(Debug,Clone)] pub struct Event{pub at:SystemTime,pub kind:EventKind,pub detail:String}
pub trait EventSink:Send+Sync{fn emit(&self,event:Event);}
#[derive(Clone,Default)] pub struct MemoryEventSink{events:Arc<Mutex<Vec<Event>>>}
impl MemoryEventSink{pub fn events(&self)->Vec<Event>{self.events.lock().expect("telemetry lock poisoned").clone()}}
impl EventSink for MemoryEventSink{fn emit(&self,event:Event){self.events.lock().expect("telemetry lock poisoned").push(event)}}
pub fn event(kind:EventKind,detail:impl Into<String>)->Event{Event{at:SystemTime::now(),kind,detail:detail.into()}}
