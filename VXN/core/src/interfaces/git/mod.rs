pub trait GitInterface {
    fn diff(&self) -> Result<String, String>;
}
