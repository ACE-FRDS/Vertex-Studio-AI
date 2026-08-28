pub trait VtcInterface {
    fn submit_candidate_transaction(&self, candidate_ref: &str) -> Result<String, String>;
    fn query_transaction_state(&self, transaction_id: &str) -> Result<String, String>;
}
