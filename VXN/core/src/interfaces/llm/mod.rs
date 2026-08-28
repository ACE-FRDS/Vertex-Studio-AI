pub trait LlmInterface {
    fn infer(&self, payload: &str) -> Result<String, String>;
}
