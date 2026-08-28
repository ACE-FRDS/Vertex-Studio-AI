use std::fmt::{Display, Formatter};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VxnError {
    Parse(String), Validation(String), Runtime(String), Security(String),
    Capability(String), Storage(String), Transport(String), Package(String), Unsupported(String),
}

impl Display for VxnError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        let (kind, msg) = match self {
            Self::Parse(v) => ("parse error", v),
            Self::Validation(v) => ("validation error", v),
            Self::Runtime(v) => ("runtime error", v),
            Self::Security(v) => ("security error", v),
            Self::Capability(v) => ("capability error", v),
            Self::Storage(v) => ("storage error", v),
            Self::Transport(v) => ("transport error", v),
            Self::Package(v) => ("package error", v),
            Self::Unsupported(v) => ("unsupported", v),
        };
        write!(f, "{kind}: {msg}")
    }
}
impl std::error::Error for VxnError {}
pub type VxnResult<T> = Result<T, VxnError>;
