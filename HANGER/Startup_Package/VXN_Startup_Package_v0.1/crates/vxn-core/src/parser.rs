use crate::{error::{VxnError,VxnResult}, ir::{Instruction,Program,Value}};

pub fn parse(source:&str)->VxnResult<Program>{
    let mut out=Vec::new();
    for (idx,raw) in source.lines().enumerate(){
        let n=idx+1; let line=raw.trim();
        if line.is_empty()||line.starts_with('#'){continue}
        let p:Vec<&str>=line.split_whitespace().collect();
        let bad=||VxnError::Parse(format!("line {n}: malformed instruction `{line}`"));
        let ins=match p.as_slice(){
            ["const",dst,val]=>Instruction::Const{dst:(*dst).into(),value:parse_value(val)},
            ["add",d,l,r]=>Instruction::Add{dst:(*d).into(),left:(*l).into(),right:(*r).into()},
            ["sub",d,l,r]=>Instruction::Sub{dst:(*d).into(),left:(*l).into(),right:(*r).into()},
            ["mul",d,l,r]=>Instruction::Mul{dst:(*d).into(),left:(*l).into(),right:(*r).into()},
            ["div",d,l,r]=>Instruction::Div{dst:(*d).into(),left:(*l).into(),right:(*r).into()},
            ["eq",d,l,r]=>Instruction::Eq{dst:(*d).into(),left:(*l).into(),right:(*r).into()},
            ["store",k,s]=>Instruction::Store{key:(*k).into(),src:(*s).into()},
            ["load",d,k]=>Instruction::Load{dst:(*d).into(),key:(*k).into()},
            ["label",x]=>Instruction::Label((*x).into()), ["jump",x]=>Instruction::Jump((*x).into()),
            ["jump_if_false",c,l]=>Instruction::JumpIfFalse{cond:(*c).into(),label:(*l).into()},
            ["print",s]=>Instruction::Print((*s).into()), ["halt"]=>Instruction::Halt,
            _=>return Err(bad()),
        }; out.push(ins);
    }
    Ok(Program::new(out))
}
fn parse_value(v:&str)->Value{ if let Ok(n)=v.parse::<i64>(){Value::Int(n)} else if v=="true"{Value::Bool(true)} else if v=="false"{Value::Bool(false)} else {Value::Text(v.into())} }

#[cfg(test)] mod tests{use super::*; #[test] fn parses(){assert_eq!(parse("const a 1\nhalt").unwrap().instructions.len(),2);}}
