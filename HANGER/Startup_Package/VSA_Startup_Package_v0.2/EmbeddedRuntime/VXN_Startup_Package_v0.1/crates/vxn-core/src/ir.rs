#[derive(Debug, Clone, PartialEq)]
pub enum Value { Int(i64), Bool(bool), Text(String), Unit }
impl Value {
    pub fn as_bool(&self) -> Option<bool> { if let Self::Bool(v)=self {Some(*v)} else {None} }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Instruction {
    Const { dst:String, value:Value }, Add { dst:String,left:String,right:String },
    Sub { dst:String,left:String,right:String }, Mul { dst:String,left:String,right:String },
    Div { dst:String,left:String,right:String }, Eq { dst:String,left:String,right:String },
    Store { key:String, src:String }, Load { dst:String, key:String },
    Label(String), Jump(String), JumpIfFalse { cond:String, label:String }, Print(String), Halt,
}
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Program { pub instructions: Vec<Instruction> }
impl Program { pub fn new(instructions:Vec<Instruction>)->Self{Self{instructions}} }
