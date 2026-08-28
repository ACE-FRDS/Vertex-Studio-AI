pub trait VxnEncode<T> {
    fn encode(&self, value: &T) -> Result<Vec<u8>, String>;
}

pub trait VxnDecode<T> {
    fn decode(&self, bytes: &[u8]) -> Result<T, String>;
}
