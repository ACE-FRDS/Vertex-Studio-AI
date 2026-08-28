use std::{collections::HashMap,sync::Arc};
use crate::{error::{VxnError,VxnResult},ir::{Instruction,Program,Value},observability::{event,EventKind,EventSink,MemoryEventSink},optimizer,security::{ExecutionPolicy,Permission},storage::{KeyValueStore,MemoryStore},validator};
#[derive(Debug,Clone,PartialEq)]pub struct ExecutionResult{pub output:Vec<Value>,pub variables:HashMap<String,Value>,pub halted:bool}
pub struct Runtime{store:Arc<dyn KeyValueStore>,policy:ExecutionPolicy,sink:Arc<dyn EventSink>}
impl Default for Runtime{fn default()->Self{Self{store:Arc::new(MemoryStore::default()),policy:ExecutionPolicy::local_safe_default(),sink:Arc::new(MemoryEventSink::default())}}}
impl Runtime{
 pub fn new(store:Arc<dyn KeyValueStore>,policy:ExecutionPolicy,sink:Arc<dyn EventSink>)->Self{Self{store,policy,sink}}
 pub fn execute(&self,program:&Program)->VxnResult<ExecutionResult>{
  validator::validate(program)?;self.sink.emit(event(EventKind::ValidationPassed,"program validated"));
  let p=optimizer::optimize(program);self.sink.emit(event(EventKind::OptimizationCompleted,"program optimized"));self.sink.emit(event(EventKind::ExecutionStarted,"execution started"));
  let labels=label_map(&p);let mut vars=HashMap::new();let mut output=Vec::new();let mut ip=0usize;let mut halted=false;
  while ip<p.instructions.len(){let ins=&p.instructions[ip];self.sink.emit(event(EventKind::InstructionExecuted,format!("{ins:?}")));match ins{
   Instruction::Const{dst,value}=>{vars.insert(dst.clone(),value.clone());},
   Instruction::Add{dst,left,right}=>{let(a,b)=ints(&vars,left,right)?;vars.insert(dst.clone(),Value::Int(a.checked_add(b).ok_or_else(||VxnError::Runtime("integer overflow".into()))?));},
   Instruction::Sub{dst,left,right}=>{let(a,b)=ints(&vars,left,right)?;vars.insert(dst.clone(),Value::Int(a.checked_sub(b).ok_or_else(||VxnError::Runtime("integer overflow".into()))?));},
   Instruction::Mul{dst,left,right}=>{let(a,b)=ints(&vars,left,right)?;vars.insert(dst.clone(),Value::Int(a.checked_mul(b).ok_or_else(||VxnError::Runtime("integer overflow".into()))?));},
   Instruction::Div{dst,left,right}=>{let(a,b)=ints(&vars,left,right)?;if b==0{return Err(VxnError::Runtime("division by zero".into()))}vars.insert(dst.clone(),Value::Int(a/b));},
   Instruction::Eq{dst,left,right}=>{let a=vars.get(left).ok_or_else(||VxnError::Runtime(format!("missing `{left}`")))?;let b=vars.get(right).ok_or_else(||VxnError::Runtime(format!("missing `{right}`")))?;vars.insert(dst.clone(),Value::Bool(a==b));},
   Instruction::Store{key,src}=>{self.policy.require(Permission::WriteState)?;let v=vars.get(src).ok_or_else(||VxnError::Runtime(format!("missing `{src}`")))?;self.store.set(key,&encode(v))?;},
   Instruction::Load{dst,key}=>{self.policy.require(Permission::ReadState)?;let raw=self.store.get(key)?.ok_or_else(||VxnError::Runtime(format!("storage key `{key}` missing")))?;vars.insert(dst.clone(),decode(&raw));},
   Instruction::Label(_)=>{},Instruction::Jump(l)=>{ip=*labels.get(l).ok_or_else(||VxnError::Runtime(format!("unknown label `{l}`")))?;continue},
   Instruction::JumpIfFalse{cond,label}=>{let b=vars.get(cond).and_then(Value::as_bool).ok_or_else(||VxnError::Runtime(format!("`{cond}` is not boolean")))?;if !b{ip=*labels.get(label).ok_or_else(||VxnError::Runtime(format!("unknown label `{label}`")))?;continue}},
   Instruction::Print(src)=>output.push(vars.get(src).cloned().ok_or_else(||VxnError::Runtime(format!("missing `{src}`")))?),
   Instruction::Halt=>{halted=true;break},
  }ip+=1;}
  self.sink.emit(event(EventKind::ExecutionCompleted,"execution completed"));Ok(ExecutionResult{output,variables:vars,halted})
 }
}
fn label_map(p:&Program)->HashMap<String,usize>{let mut m=HashMap::new();for(i,ins)in p.instructions.iter().enumerate(){if let Instruction::Label(n)=ins{m.insert(n.clone(),i);}}m}
fn ints(v:&HashMap<String,Value>,l:&str,r:&str)->VxnResult<(i64,i64)>{fn one(v:&HashMap<String,Value>,n:&str)->VxnResult<i64>{match v.get(n){Some(Value::Int(x))=>Ok(*x),Some(_)=>Err(VxnError::Runtime(format!("`{n}` is not integer"))),None=>Err(VxnError::Runtime(format!("missing `{n}`")))}}Ok((one(v,l)?,one(v,r)?))}
fn encode(v:&Value)->String{match v{Value::Int(n)=>format!("i:{n}"),Value::Bool(b)=>format!("b:{b}"),Value::Text(s)=>format!("s:{s}"),Value::Unit=>"u:".into()}}
fn decode(s:&str)->Value{if let Some(v)=s.strip_prefix("i:").and_then(|x|x.parse().ok()){return Value::Int(v)}if let Some(v)=s.strip_prefix("b:").and_then(|x|x.parse().ok()){return Value::Bool(v)}if let Some(v)=s.strip_prefix("s:"){return Value::Text(v.into())}Value::Unit}
#[cfg(test)]mod tests{use super::*;use crate::parser::parse;
 #[test]fn add(){let r=Runtime::default().execute(&parse("const a 1\nconst b 2\nadd c a b\nprint c\nhalt").unwrap()).unwrap();assert_eq!(r.output,vec![Value::Int(3)]);}
 #[test]fn storage(){let r=Runtime::default().execute(&parse("const value 42\nstore answer value\nload loaded answer\nprint loaded\nhalt").unwrap()).unwrap();assert_eq!(r.output,vec![Value::Int(42)]);}
 #[test]fn branch(){let s="const x 5\nconst y 5\neq same x y\njump_if_false same not_equal\nconst answer 1\nprint answer\njump end\nlabel not_equal\nconst answer 0\nprint answer\nlabel end\nhalt";let r=Runtime::default().execute(&parse(s).unwrap()).unwrap();assert_eq!(r.output,vec![Value::Int(1)]);}
}
