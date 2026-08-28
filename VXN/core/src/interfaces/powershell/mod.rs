pub trait PowerShellInterface {
    fn invoke_candidate(&self, ref_id: &str) -> Result<String, String>;
}
