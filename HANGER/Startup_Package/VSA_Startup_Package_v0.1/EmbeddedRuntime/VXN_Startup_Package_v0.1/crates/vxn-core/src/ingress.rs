#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IngressKind { NaturalLanguage, Gui, Voice, Diagram, Script, StructuredDefinition }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IngressEnvelope { pub kind:IngressKind, pub content:String, pub language:Option<String> }
impl IngressEnvelope { pub fn new(kind:IngressKind, content:impl Into<String>)->Self{Self{kind,content:content.into(),language:None}} }
