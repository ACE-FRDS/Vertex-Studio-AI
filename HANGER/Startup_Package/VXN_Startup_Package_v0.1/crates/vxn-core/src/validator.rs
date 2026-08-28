use std::collections::{HashMap,HashSet};
use crate::{error::{VxnError,VxnResult},ir::{Instruction,Program}};
pub fn validate(program:&Program)->VxnResult<()> {
    let mut labels=HashMap::new();
    for (i,ins) in program.instructions.iter().enumerate(){ if let Instruction::Label(n)=ins { if labels.insert(n.clone(),i).is_some(){return Err(VxnError::Validation(format!("duplicate label `{n}`")))}}}
    for ins in &program.instructions {match ins {Instruction::Jump(n)|Instruction::JumpIfFalse{label:n,..} if !labels.contains_key(n)=>return Err(VxnError::Validation(format!("unknown label `{n}`"))), _=>{}}}
    let mut defined=HashSet::new();
    for ins in &program.instructions {match ins {
        Instruction::Const{dst,..}|Instruction::Load{dst,..}=>{defined.insert(dst.clone());},
        Instruction::Add{dst,left,right}|Instruction::Sub{dst,left,right}|Instruction::Mul{dst,left,right}|Instruction::Div{dst,left,right}|Instruction::Eq{dst,left,right}=>{need(&defined,left)?;need(&defined,right)?;defined.insert(dst.clone());},
        Instruction::Store{src,..}|Instruction::Print(src)=>need(&defined,src)?, Instruction::JumpIfFalse{cond,..}=>need(&defined,cond)?, _=>{}
    }} Ok(())
}
fn need(set:&HashSet<String>,name:&str)->VxnResult<()> {if set.contains(name){Ok(())}else{Err(VxnError::Validation(format!("variable `{name}` used before definition")))}}
