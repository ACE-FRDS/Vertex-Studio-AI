use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct VxnId(pub Uuid);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum VxnValue {
    Null,
    Bool(bool),
    I64(i64),
    F64(f64),
    Utf8(String),
    Bytes(Vec<u8>),
    Ref(VxnId),
    List(Vec<VxnValue>),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VxnOperation {
    pub op_code: u32,
    pub target: VxnId,
    pub property_code: Option<u32>,
    pub old_value: Option<VxnValue>,
    pub new_value: Option<VxnValue>,
    pub flags: u64,
}
