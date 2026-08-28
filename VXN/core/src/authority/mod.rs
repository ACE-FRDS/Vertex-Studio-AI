#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Authority {
    Observe,
    Propose,
    CandidateWrite,
    HumanApprove,
    Execute,
    Commit,
}

pub const VXN_DEFAULT_AUTHORITY: Authority = Authority::Propose;
