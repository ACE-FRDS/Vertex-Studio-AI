use crate::private_control::{
    PRIVATE_PATCH_SCHEMA, PrivatePatchPreview, PrivatePatchRequest, read_private_source_snapshot,
    stage_private_patch,
};
use serde::{Deserialize, Serialize};
use std::path::Path;

pub const PRIVATE_TEXT_PATCH_SCHEMA: &str = "vertex.private-hub.text-patch.v0.2";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PrivateTextReplacement {
    pub find: String,
    pub replace: String,
    pub expected_occurrences: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PrivateTextPatchRequest {
    pub schema: String,
    pub request_id: String,
    pub actor: String,
    pub reason: String,
    pub relative_path: String,
    pub expected_sha256: String,
    pub operations: Vec<PrivateTextReplacement>,
}

pub fn stage_private_text_patch(
    workspace_root: &Path,
    control_root: &Path,
    request: &PrivateTextPatchRequest,
) -> Result<PrivatePatchPreview, String> {
    if request.schema != PRIVATE_TEXT_PATCH_SCHEMA {
        return Err(format!(
            "unsupported Private VertexHub text-patch schema: {}",
            request.schema
        ));
    }

    if request.operations.is_empty() {
        return Err("Private VertexHub text patch requires at least one operation".into());
    }

    let snapshot = read_private_source_snapshot(workspace_root, &request.relative_path)?;

    let expected_sha256 = request.expected_sha256.to_ascii_lowercase();

    if snapshot.sha256 != expected_sha256 {
        return Err(format!(
            "Private VertexHub text-patch SHA-256 lock mismatch: expected={} actual={}",
            expected_sha256, snapshot.sha256
        ));
    }

    let mut replacement_content = snapshot.content.clone();

    for (index, operation) in request.operations.iter().enumerate() {
        if operation.find.is_empty() {
            return Err(format!(
                "Private VertexHub text-patch operation {} has empty find text",
                index + 1
            ));
        }

        if operation.expected_occurrences == 0 {
            return Err(format!(
                "Private VertexHub text-patch operation {} must expect at least one occurrence",
                index + 1
            ));
        }

        let actual_occurrences = replacement_content.match_indices(&operation.find).count();

        if actual_occurrences != operation.expected_occurrences {
            return Err(format!(
                "Private VertexHub text-patch operation {} occurrence mismatch: expected={} actual={}",
                index + 1,
                operation.expected_occurrences,
                actual_occurrences
            ));
        }

        replacement_content = replacement_content.replace(&operation.find, &operation.replace);
    }

    if replacement_content == snapshot.content {
        return Err("Private VertexHub text patch produces no source change".into());
    }

    let full_request = PrivatePatchRequest {
        schema: PRIVATE_PATCH_SCHEMA.to_string(),
        request_id: request.request_id.clone(),
        actor: request.actor.clone(),
        reason: request.reason.clone(),
        relative_path: request.relative_path.clone(),
        expected_sha256: request.expected_sha256.clone(),
        replacement_content,
    };

    stage_private_patch(workspace_root, control_root, &full_request)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::private_control::{
        HumanApproval, apply_staged_private_patch, read_private_source_snapshot,
    };
    use sha2::{Digest, Sha256};
    use std::fs;
    use std::path::PathBuf;

    fn now_ms() -> u128 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis()
    }

    fn unique_test_root(label: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "vsa-private-transport-{label}-{}-{}",
            std::process::id(),
            now_ms()
        ))
    }

    fn sha256_text(value: &str) -> String {
        let digest = Sha256::digest(value.as_bytes());
        digest.iter().map(|byte| format!("{byte:02x}")).collect()
    }

    fn write_fixture(root: &Path, relative: &str, content: &str) {
        let path = root.join(relative);
        fs::create_dir_all(path.parent().expect("fixture parent")).expect("create fixture parent");
        fs::write(path, content).expect("write fixture");
    }

    #[test]
    fn compact_text_patch_stages_and_applies() {
        let workspace = unique_test_root("apply-workspace");
        let control = unique_test_root("apply-control");
        let relative = "crates/demo/src/lib.rs";
        let original = "pub fn value() -> u8 { 1 }\n";

        write_fixture(&workspace, relative, original);

        let request = PrivateTextPatchRequest {
            schema: PRIVATE_TEXT_PATCH_SCHEMA.into(),
            request_id: "transport-apply".into(),
            actor: "chappy".into(),
            reason: "compact patch transport test".into(),
            relative_path: relative.into(),
            expected_sha256: sha256_text(original),
            operations: vec![PrivateTextReplacement {
                find: "{ 1 }".into(),
                replace: "{ 2 }".into(),
                expected_occurrences: 1,
            }],
        };

        let preview =
            stage_private_text_patch(&workspace, &control, &request).expect("stage text patch");

        assert!(preview.ready);
        assert!(preview.human_gate_required);

        let receipt = apply_staged_private_patch(
            &workspace,
            &control,
            &request.request_id,
            &HumanApproval {
                request_id: request.request_id.clone(),
                approved: true,
                approved_by: "human".into(),
            },
        )
        .expect("apply staged text patch");

        let snapshot =
            read_private_source_snapshot(&workspace, relative).expect("read patched source");

        assert_eq!(snapshot.content, "pub fn value() -> u8 { 2 }\n");
        assert_eq!(snapshot.sha256, receipt.applied_sha256);

        let _ = fs::remove_dir_all(workspace);
        let _ = fs::remove_dir_all(control);
    }

    #[test]
    fn compact_text_patch_rejects_ambiguous_occurrence_count() {
        let workspace = unique_test_root("count-workspace");
        let control = unique_test_root("count-control");
        let relative = "crates/demo/src/lib.rs";
        let original = "alpha\nalpha\n";

        write_fixture(&workspace, relative, original);

        let request = PrivateTextPatchRequest {
            schema: PRIVATE_TEXT_PATCH_SCHEMA.into(),
            request_id: "transport-count".into(),
            actor: "chappy".into(),
            reason: "reject ambiguous text replacement".into(),
            relative_path: relative.into(),
            expected_sha256: sha256_text(original),
            operations: vec![PrivateTextReplacement {
                find: "alpha".into(),
                replace: "beta".into(),
                expected_occurrences: 1,
            }],
        };

        let error = stage_private_text_patch(&workspace, &control, &request)
            .expect_err("must reject count");

        assert!(error.contains("occurrence mismatch"));

        let _ = fs::remove_dir_all(workspace);
        let _ = fs::remove_dir_all(control);
    }
}
