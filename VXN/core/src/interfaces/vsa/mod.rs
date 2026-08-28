pub trait VsaInterface {
    fn emit_observation(&self, observation_ref: &str) -> Result<(), String>;
    fn request_human_gate(&self, gate_ref: &str) -> Result<(), String>;
}
