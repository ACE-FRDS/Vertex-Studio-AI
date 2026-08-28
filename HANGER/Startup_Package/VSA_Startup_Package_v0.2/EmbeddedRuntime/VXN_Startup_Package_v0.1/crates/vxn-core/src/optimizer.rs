use std::collections::HashMap;
use crate::ir::{Instruction,Program,Value};
pub fn optimize(program:&Program)->Program{
    let mut c:HashMap<String,Value>=HashMap::new(); let mut out=Vec::new();
    for ins in &program.instructions {match ins {
        Instruction::Const{dst,value}=>{c.insert(dst.clone(),value.clone());out.push(ins.clone());},
        Instruction::Add{dst,left,right}|Instruction::Sub{dst,left,right}|Instruction::Mul{dst,left,right}|Instruction::Div{dst,left,right}=>{
            let folded=match(c.get(left),c.get(right)){(Some(Value::Int(a)),Some(Value::Int(b)))=>match ins{Instruction::Add{..}=>a.checked_add(*b),Instruction::Sub{..}=>a.checked_sub(*b),Instruction::Mul{..}=>a.checked_mul(*b),Instruction::Div{..} if *b!=0=>Some(a/b),_=>None},_=>None};
            if let Some(v)=folded{c.insert(dst.clone(),Value::Int(v));out.push(Instruction::Const{dst:dst.clone(),value:Value::Int(v)});}else{c.remove(dst);out.push(ins.clone());}
        },
        Instruction::Eq{dst,left,right}=>{if let(Some(a),Some(b))=(c.get(left),c.get(right)){let v=Value::Bool(a==b);c.insert(dst.clone(),v.clone());out.push(Instruction::Const{dst:dst.clone(),value:v});}else{c.remove(dst);out.push(ins.clone());}},
        Instruction::Load{dst,..}=>{c.remove(dst);out.push(ins.clone());}, _=>out.push(ins.clone())
    }} Program::new(out)
}
