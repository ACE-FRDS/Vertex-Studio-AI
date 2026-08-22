use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct ObjectId(pub [u8; 32]);

pub fn content_id(bytes: &[u8]) -> ObjectId {
    ObjectId(Sha256::digest(bytes).into())
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WorldObject {
    pub semantic_type: String,
    pub payload: serde_json::Value,
}

impl WorldObject {
    pub fn id(&self) -> ObjectId {
        content_id(&serde_json::to_vec(self).expect("serializable world object"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ids_are_content_addressed() {
        let a=WorldObject{semantic_type:"State".into(),payload:serde_json::json!({"x":1})};
        let b=a.clone();
        assert_eq!(a.id(),b.id());
    }
}
