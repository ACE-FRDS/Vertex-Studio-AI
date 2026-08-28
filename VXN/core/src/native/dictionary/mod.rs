use std::collections::HashMap;

#[derive(Default)]
pub struct VxnDictionary {
    pub symbols: HashMap<String, u32>,
    pub reverse: HashMap<u32, String>,
}
