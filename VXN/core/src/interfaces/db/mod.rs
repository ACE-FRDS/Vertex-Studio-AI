pub trait DbInterface {
    fn query(&self, request: &str) -> Result<String, String>;
}
