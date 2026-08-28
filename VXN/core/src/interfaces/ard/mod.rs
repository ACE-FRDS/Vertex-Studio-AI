pub trait ArdInterface {
    fn submit_mission(&self, mission_ref: &str) -> Result<String, String>;
}
