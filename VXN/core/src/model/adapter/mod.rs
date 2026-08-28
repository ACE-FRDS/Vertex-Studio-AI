pub trait ModelAdapter: Send + Sync {
    fn model_id(&self) -> &str;
    fn encode_for_model(&self, vxn_payload: &[u8]) -> Result<String, String>;
    fn decode_from_model(&self, model_output: &str) -> Result<Vec<u8>, String>;
}
