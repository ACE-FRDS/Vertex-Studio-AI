use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::io::Write;
use std::path::{Component, Path, PathBuf};

pub const PRIVATE_PATCH_SCHEMA: &str = "vertex.private-hub.patch.v0.1";
pub const PRIVATE_PATCH_RECEIPT_SCHEMA: &str = "vertex.private-hub.patch-receipt.v0.1";
pub const PRIVATE_AUDIT_SCHEMA: &str = "vertex.private-hub.audit.v0.1";

const DEFAULT_MAX_PATCH_BYTES: usize = 262_144;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PrivatePatchRequest {
    pub schema: String,
    pub request_id: String,
    pub actor: String,
    pub reason: String,
    pub relative_path: String,
    pub expected_sha256: String,
    pub replacement_content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PrivatePatchPreview {
    pub request_id: String,
    pub relative_path: String,
    pub current_sha256: String,
    pub replacement_sha256: String,
    pub current_bytes: u64,
    pub replacement_bytes: u64,
    pub human_gate_required: bool,
    pub ready: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HumanApproval {
    pub request_id: String,
    pub approved: bool,
    pub approved_by: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PrivatePatchReceipt {
    pub schema: String,
    pub request_id: String,
    pub relative_path: String,
    pub previous_sha256: String,
    pub applied_sha256: String,
    pub backup_path: String,
    pub approved_by: String,
    pub applied_at_ms: u128,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PrivateSourceSnapshot {
    pub relative_path: String,
    pub bytes: u64,
    pub sha256: String,
    pub content: String,
}

fn now_ms() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

fn sha256_bytes(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn sha256_file(path: &Path) -> Result<String, String> {
    let bytes =
        fs::read(path).map_err(|error| format!("cannot read {}: {error}", path.display()))?;
    Ok(sha256_bytes(&bytes))
}

fn private_identity(value: &str, label: &str) -> Result<(), String> {
    if value.is_empty()
        || !value
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || "._-".contains(character))
    {
        return Err(format!("unsafe Private VertexHub {label}: {value}"));
    }

    Ok(())
}

fn safe_relative(value: &str) -> Result<PathBuf, String> {
    let path = Path::new(value);

    if path.as_os_str().is_empty() || path.is_absolute() {
        return Err(format!("unsafe Private VertexHub path: {value}"));
    }

    for component in path.components() {
        match component {
            Component::Normal(_) | Component::CurDir => {}
            _ => return Err(format!("unsafe Private VertexHub path component: {value}")),
        }
    }

    Ok(path.to_path_buf())
}

fn denied_component(component: &str) -> bool {
    matches!(
        component.to_ascii_lowercase().as_str(),
        ".git"
            | ".idea"
            | ".vscode"
            | "node_modules"
            | "target"
            | "dist"
            | "build"
            | "coverage"
            | ".cache"
            | "_vertex_reports"
    )
}

fn validate_relative_policy(relative: &Path) -> Result<(), String> {
    for component in relative.components() {
        if let Component::Normal(value) = component {
            let value = value.to_string_lossy();
            if denied_component(&value) {
                return Err(format!(
                    "Private VertexHub path denied by directory policy: {}",
                    relative.display()
                ));
            }
        }
    }

    let file_name = relative
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| {
            format!(
                "Private VertexHub target has no UTF-8 file name: {}",
                relative.display()
            )
        })?
        .to_ascii_lowercase();

    let sensitive_name = file_name == ".env"
        || file_name.contains("token")
        || file_name.contains("secret")
        || file_name.contains("credential")
        || file_name.contains("password")
        || file_name.ends_with(".pem")
        || file_name.ends_with(".key")
        || file_name.ends_with(".pfx")
        || file_name.ends_with(".p12");

    if sensitive_name {
        return Err(format!(
            "Private VertexHub target denied by sensitive-name policy: {}",
            relative.display()
        ));
    }

    let extension = relative
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();

    let allowed = matches!(
        extension.as_str(),
        "rs" | "toml"
            | "vue"
            | "ts"
            | "tsx"
            | "js"
            | "json"
            | "md"
            | "css"
            | "yaml"
            | "yml"
            | "vxn"
            | "txt"
    );

    if !allowed {
        return Err(format!(
            "Private VertexHub target extension is not allowlisted: {}",
            relative.display()
        ));
    }

    Ok(())
}

fn resolve_existing_target(
    workspace_root: &Path,
    relative_value: &str,
) -> Result<(PathBuf, PathBuf), String> {
    let relative = safe_relative(relative_value)?;
    validate_relative_policy(&relative)?;

    let canonical_root = fs::canonicalize(workspace_root).map_err(|error| {
        format!(
            "cannot canonicalize workspace root {}: {error}",
            workspace_root.display()
        )
    })?;

    let joined = workspace_root.join(&relative);

    if !joined.is_file() {
        return Err(format!(
            "Private VertexHub v0.1 only patches existing files: {}",
            joined.display()
        ));
    }

    let canonical_target = fs::canonicalize(&joined)
        .map_err(|error| format!("cannot canonicalize target {}: {error}", joined.display()))?;

    if !canonical_target.starts_with(&canonical_root) {
        return Err(format!(
            "Private VertexHub target escapes workspace root: {}",
            canonical_target.display()
        ));
    }

    Ok((relative, canonical_target))
}

fn control_staged_dir(control_root: &Path) -> PathBuf {
    control_root.join("staged")
}

fn control_backups_dir(control_root: &Path) -> PathBuf {
    control_root.join("backups")
}

fn control_audit_path(control_root: &Path) -> PathBuf {
    control_root.join("audit.ndjson")
}

fn staged_request_path(control_root: &Path, request_id: &str) -> Result<PathBuf, String> {
    private_identity(request_id, "request_id")?;
    Ok(control_staged_dir(control_root).join(format!("{request_id}.json")))
}

fn append_private_audit(
    control_root: &Path,
    action: &str,
    request_id: &str,
    relative_path: &str,
    actor: &str,
    detail: serde_json::Value,
) -> Result<(), String> {
    fs::create_dir_all(control_root)
        .map_err(|error| format!("cannot create {}: {error}", control_root.display()))?;

    let path = control_audit_path(control_root);

    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .map_err(|error| format!("cannot open {}: {error}", path.display()))?;

    let record = serde_json::json!({
        "schema": PRIVATE_AUDIT_SCHEMA,
        "timestamp_ms": now_ms(),
        "action": action,
        "request_id": request_id,
        "relative_path": relative_path,
        "actor": actor,
        "detail": detail
    });

    writeln!(file, "{record}").map_err(|error| format!("cannot append {}: {error}", path.display()))
}

pub fn read_private_source_snapshot(
    workspace_root: &Path,
    relative_path: &str,
) -> Result<PrivateSourceSnapshot, String> {
    let (relative, target) = resolve_existing_target(workspace_root, relative_path)?;

    let bytes =
        fs::read(&target).map_err(|error| format!("cannot read {}: {error}", target.display()))?;

    if bytes.len() > DEFAULT_MAX_PATCH_BYTES {
        return Err(format!(
            "Private VertexHub source exceeds v0.1 size limit: {} bytes",
            bytes.len()
        ));
    }

    let content = String::from_utf8(bytes.clone()).map_err(|_| {
        format!(
            "Private VertexHub source is not UTF-8: {}",
            target.display()
        )
    })?;

    Ok(PrivateSourceSnapshot {
        relative_path: relative.to_string_lossy().replace('\\', "/"),
        bytes: bytes.len() as u64,
        sha256: sha256_bytes(&bytes),
        content,
    })
}

pub fn stage_private_patch(
    workspace_root: &Path,
    control_root: &Path,
    request: &PrivatePatchRequest,
) -> Result<PrivatePatchPreview, String> {
    if request.schema != PRIVATE_PATCH_SCHEMA {
        return Err(format!(
            "unsupported Private VertexHub patch schema: {}",
            request.schema
        ));
    }

    private_identity(&request.request_id, "request_id")?;

    if request.actor.trim().is_empty() {
        return Err("Private VertexHub patch actor is required".into());
    }

    if request.reason.trim().is_empty() {
        return Err("Private VertexHub patch reason is required".into());
    }

    if request.replacement_content.len() > DEFAULT_MAX_PATCH_BYTES {
        return Err(format!(
            "Private VertexHub replacement exceeds v0.1 size limit: {} bytes",
            request.replacement_content.len()
        ));
    }

    let (relative, target) = resolve_existing_target(workspace_root, &request.relative_path)?;

    let current_bytes =
        fs::read(&target).map_err(|error| format!("cannot read {}: {error}", target.display()))?;

    let current_sha256 = sha256_bytes(&current_bytes);
    let expected = request.expected_sha256.to_ascii_lowercase();

    if current_sha256 != expected {
        return Err(format!(
            "Private VertexHub SHA-256 lock mismatch: expected={} actual={}",
            expected, current_sha256
        ));
    }

    let replacement_sha256 = sha256_bytes(request.replacement_content.as_bytes());

    let staged_path = staged_request_path(control_root, &request.request_id)?;

    if staged_path.exists() {
        return Err(format!(
            "Private VertexHub staged request already exists: {}",
            request.request_id
        ));
    }

    fs::create_dir_all(control_staged_dir(control_root))
        .map_err(|error| format!("cannot create staged directory: {error}"))?;

    let staged_bytes = serde_json::to_vec_pretty(request)
        .map_err(|error| format!("cannot serialize Private VertexHub patch: {error}"))?;

    let temp = staged_path.with_extension("json.tmp");

    fs::write(&temp, staged_bytes)
        .map_err(|error| format!("cannot write {}: {error}", temp.display()))?;

    fs::rename(&temp, &staged_path)
        .map_err(|error| format!("cannot commit {}: {error}", staged_path.display()))?;

    append_private_audit(
        control_root,
        "STAGE",
        &request.request_id,
        &relative.to_string_lossy(),
        &request.actor,
        serde_json::json!({
            "current_sha256": current_sha256,
            "replacement_sha256": replacement_sha256,
            "current_bytes": current_bytes.len(),
            "replacement_bytes": request.replacement_content.len()
        }),
    )?;

    Ok(PrivatePatchPreview {
        request_id: request.request_id.clone(),
        relative_path: relative.to_string_lossy().replace('\\', "/"),
        current_sha256,
        replacement_sha256,
        current_bytes: current_bytes.len() as u64,
        replacement_bytes: request.replacement_content.len() as u64,
        human_gate_required: true,
        ready: true,
    })
}

fn load_staged_request(
    control_root: &Path,
    request_id: &str,
) -> Result<(PathBuf, PrivatePatchRequest), String> {
    let path = staged_request_path(control_root, request_id)?;

    let request: PrivatePatchRequest = serde_json::from_slice(
        &fs::read(&path).map_err(|error| format!("cannot read {}: {error}", path.display()))?,
    )
    .map_err(|error| format!("invalid staged Private VertexHub patch JSON: {error}"))?;

    if request.request_id != request_id {
        return Err(format!(
            "Private VertexHub staged request identity mismatch: file={} payload={}",
            request_id, request.request_id
        ));
    }

    Ok((path, request))
}

fn backup_path_for(
    control_root: &Path,
    request_id: &str,
    relative: &Path,
) -> Result<PathBuf, String> {
    private_identity(request_id, "request_id")?;
    validate_relative_policy(relative)?;

    Ok(control_backups_dir(control_root)
        .join(request_id)
        .join(relative))
}

pub fn apply_staged_private_patch(
    workspace_root: &Path,
    control_root: &Path,
    request_id: &str,
    approval: &HumanApproval,
) -> Result<PrivatePatchReceipt, String> {
    private_identity(request_id, "request_id")?;

    if approval.request_id != request_id {
        return Err("Private VertexHub Human Gate request identity mismatch".into());
    }

    if !approval.approved {
        return Err("Private VertexHub Human Gate rejected patch".into());
    }

    if approval.approved_by.trim().is_empty() {
        return Err("Private VertexHub Human Gate approver is required".into());
    }

    let (staged_path, request) = load_staged_request(control_root, request_id)?;
    let (relative, target) = resolve_existing_target(workspace_root, &request.relative_path)?;

    let current_sha256 = sha256_file(&target)?;
    let expected = request.expected_sha256.to_ascii_lowercase();

    if current_sha256 != expected {
        return Err(format!(
            "Private VertexHub apply rejected: source changed after staging; expected={} actual={}",
            expected, current_sha256
        ));
    }

    let replacement_bytes = request.replacement_content.as_bytes();

    if replacement_bytes.len() > DEFAULT_MAX_PATCH_BYTES {
        return Err("Private VertexHub replacement exceeds v0.1 size limit".into());
    }

    let replacement_sha256 = sha256_bytes(replacement_bytes);
    let backup_path = backup_path_for(control_root, request_id, &relative)?;

    if backup_path.exists() {
        return Err(format!(
            "Private VertexHub backup already exists for request: {}",
            request_id
        ));
    }

    if let Some(parent) = backup_path.parent() {
        fs::create_dir_all(parent).map_err(|error| {
            format!(
                "cannot create backup directory {}: {error}",
                parent.display()
            )
        })?;
    }

    fs::copy(&target, &backup_path).map_err(|error| {
        format!(
            "cannot create Private VertexHub backup {} -> {}: {error}",
            target.display(),
            backup_path.display()
        )
    })?;

    let parent = target.parent().ok_or_else(|| {
        format!(
            "Private VertexHub target has no parent: {}",
            target.display()
        )
    })?;

    let file_name = target
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| {
            format!(
                "Private VertexHub target has no UTF-8 file name: {}",
                target.display()
            )
        })?;

    let temp = parent.join(format!(".{file_name}.vertex-patch-{request_id}.tmp"));
    let rollback_slot = parent.join(format!(".{file_name}.vertex-rollback-{request_id}.tmp"));

    if temp.exists() || rollback_slot.exists() {
        return Err("Private VertexHub transaction temp path already exists".into());
    }

    fs::write(&temp, replacement_bytes).map_err(|error| {
        format!(
            "cannot write Private VertexHub temp file {}: {error}",
            temp.display()
        )
    })?;

    let temp_hash = sha256_file(&temp)?;

    if temp_hash != replacement_sha256 {
        let _ = fs::remove_file(&temp);
        return Err("Private VertexHub temp-file integrity check failed".into());
    }

    append_private_audit(
        control_root,
        "APPLY_BEGIN",
        request_id,
        &relative.to_string_lossy(),
        &request.actor,
        serde_json::json!({
            "approved_by": approval.approved_by,
            "previous_sha256": current_sha256,
            "replacement_sha256": replacement_sha256
        }),
    )?;

    fs::rename(&target, &rollback_slot).map_err(|error| {
        let _ = fs::remove_file(&temp);
        format!(
            "cannot move current source into rollback slot {}: {error}",
            rollback_slot.display()
        )
    })?;

    if let Err(error) = fs::rename(&temp, &target) {
        let restore = fs::rename(&rollback_slot, &target);
        let _ = fs::remove_file(&temp);

        return match restore {
            Ok(()) => Err(format!(
                "Private VertexHub apply failed and source was restored: {error}"
            )),
            Err(restore_error) => Err(format!(
                "CRITICAL: Private VertexHub apply failed and automatic restore also failed: apply={error}; restore={restore_error}"
            )),
        };
    }

    let applied_hash = match sha256_file(&target) {
        Ok(hash) => hash,
        Err(error) => {
            let _ = fs::remove_file(&target);
            let _ = fs::rename(&rollback_slot, &target);
            return Err(format!(
                "Private VertexHub post-apply hash read failed; rollback attempted: {error}"
            ));
        }
    };

    if applied_hash != replacement_sha256 {
        let _ = fs::remove_file(&target);
        let restore = fs::rename(&rollback_slot, &target);

        return match restore {
            Ok(()) => {
                Err("Private VertexHub post-apply integrity mismatch; source restored".into())
            }
            Err(restore_error) => Err(format!(
                "CRITICAL: Private VertexHub integrity mismatch and restore failed: {restore_error}"
            )),
        };
    }

    let _ = fs::remove_file(&rollback_slot);

    let receipt = PrivatePatchReceipt {
        schema: PRIVATE_PATCH_RECEIPT_SCHEMA.to_string(),
        request_id: request_id.to_string(),
        relative_path: relative.to_string_lossy().replace('\\', "/"),
        previous_sha256: current_sha256.clone(),
        applied_sha256: applied_hash.clone(),
        backup_path: backup_path.to_string_lossy().to_string(),
        approved_by: approval.approved_by.clone(),
        applied_at_ms: now_ms(),
    };

    if let Err(error) = append_private_audit(
        control_root,
        "APPLY_COMMIT",
        request_id,
        &relative.to_string_lossy(),
        &request.actor,
        serde_json::json!({
            "approved_by": approval.approved_by,
            "previous_sha256": current_sha256,
            "applied_sha256": applied_hash,
            "backup_path": backup_path
        }),
    ) {
        let current_after_apply = sha256_file(&target).unwrap_or_default();

        if current_after_apply == receipt.applied_sha256 {
            let restore_temp = parent.join(format!(
                ".{file_name}.vertex-audit-rollback-{request_id}.tmp"
            ));

            if fs::copy(&backup_path, &restore_temp).is_ok() {
                let _ = fs::remove_file(&target);
                let _ = fs::rename(&restore_temp, &target);
            }
        }

        return Err(format!(
            "Private VertexHub audit commit failed; rollback attempted: {error}"
        ));
    }

    fs::remove_file(&staged_path).map_err(|error| {
        format!(
            "patch applied but cannot remove staged request {}: {error}",
            staged_path.display()
        )
    })?;

    Ok(receipt)
}

pub fn rollback_private_patch(
    workspace_root: &Path,
    control_root: &Path,
    receipt: &PrivatePatchReceipt,
    approved_by: &str,
) -> Result<PrivateSourceSnapshot, String> {
    if receipt.schema != PRIVATE_PATCH_RECEIPT_SCHEMA {
        return Err(format!(
            "unsupported Private VertexHub receipt schema: {}",
            receipt.schema
        ));
    }

    private_identity(&receipt.request_id, "request_id")?;

    if approved_by.trim().is_empty() {
        return Err("Private VertexHub rollback approver is required".into());
    }

    let (relative, target) = resolve_existing_target(workspace_root, &receipt.relative_path)?;

    let current_hash = sha256_file(&target)?;

    if current_hash != receipt.applied_sha256 {
        return Err(format!(
            "Private VertexHub rollback rejected: current source changed after apply; expected={} actual={}",
            receipt.applied_sha256, current_hash
        ));
    }

    let backup_path = PathBuf::from(&receipt.backup_path);

    if !backup_path.is_file() {
        return Err(format!(
            "Private VertexHub rollback backup is missing: {}",
            backup_path.display()
        ));
    }

    let backup_hash = sha256_file(&backup_path)?;

    if backup_hash != receipt.previous_sha256 {
        return Err(format!(
            "Private VertexHub rollback backup integrity mismatch: expected={} actual={}",
            receipt.previous_sha256, backup_hash
        ));
    }

    let parent = target.parent().ok_or_else(|| {
        format!(
            "Private VertexHub target has no parent: {}",
            target.display()
        )
    })?;

    let file_name = target
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| {
            format!(
                "Private VertexHub target has no UTF-8 file name: {}",
                target.display()
            )
        })?;

    let temp = parent.join(format!(
        ".{file_name}.vertex-manual-rollback-{}.tmp",
        receipt.request_id
    ));

    if temp.exists() {
        return Err("Private VertexHub rollback temp path already exists".into());
    }

    fs::copy(&backup_path, &temp)
        .map_err(|error| format!("cannot stage Private VertexHub rollback: {error}"))?;

    let temp_hash = sha256_file(&temp)?;

    if temp_hash != receipt.previous_sha256 {
        let _ = fs::remove_file(&temp);
        return Err("Private VertexHub rollback temp integrity mismatch".into());
    }

    let rollback_slot = parent.join(format!(
        ".{file_name}.vertex-pre-rollback-{}.tmp",
        receipt.request_id
    ));

    fs::rename(&target, &rollback_slot)
        .map_err(|error| format!("cannot stage current source for rollback: {error}"))?;

    if let Err(error) = fs::rename(&temp, &target) {
        let restore = fs::rename(&rollback_slot, &target);
        let _ = fs::remove_file(&temp);

        return match restore {
            Ok(()) => Err(format!(
                "Private VertexHub rollback failed and patched source was restored: {error}"
            )),
            Err(restore_error) => Err(format!(
                "CRITICAL: Private VertexHub rollback failed and patched source restore failed: rollback={error}; restore={restore_error}"
            )),
        };
    }

    let _ = fs::remove_file(&rollback_slot);

    append_private_audit(
        control_root,
        "ROLLBACK",
        &receipt.request_id,
        &relative.to_string_lossy(),
        approved_by,
        serde_json::json!({
            "restored_sha256": receipt.previous_sha256,
            "replaced_sha256": receipt.applied_sha256
        }),
    )?;

    read_private_source_snapshot(workspace_root, &receipt.relative_path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn unique_test_root(label: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "vsa-private-hub-{label}-{}-{}",
            std::process::id(),
            now_ms()
        ))
    }

    fn write_fixture(root: &Path, relative: &str, content: &str) -> PathBuf {
        let path = root.join(relative);
        fs::create_dir_all(path.parent().expect("fixture parent")).expect("create fixture parent");
        fs::write(&path, content).expect("write fixture");
        path
    }

    #[test]
    fn private_path_traversal_is_denied() {
        let root = unique_test_root("traversal");
        fs::create_dir_all(&root).expect("create test root");

        assert!(resolve_existing_target(&root, "../secret.rs").is_err());
        assert!(resolve_existing_target(&root, "target/debug.rs").is_err());

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn stage_rejects_stale_sha_lock() {
        let workspace = unique_test_root("stale-workspace");
        let control = unique_test_root("stale-control");

        write_fixture(&workspace, "crates/demo/src/lib.rs", "pub fn old() {}\n");

        let request = PrivatePatchRequest {
            schema: PRIVATE_PATCH_SCHEMA.into(),
            request_id: "request-stale".into(),
            actor: "chappy".into(),
            reason: "test stale hash".into(),
            relative_path: "crates/demo/src/lib.rs".into(),
            expected_sha256: "00".repeat(32),
            replacement_content: "pub fn new() {}\n".into(),
        };

        assert!(stage_private_patch(&workspace, &control, &request).is_err());

        let _ = fs::remove_dir_all(workspace);
        let _ = fs::remove_dir_all(control);
    }

    #[test]
    fn stage_apply_and_rollback_round_trip() {
        let workspace = unique_test_root("roundtrip-workspace");
        let control = unique_test_root("roundtrip-control");

        let target = write_fixture(
            &workspace,
            "crates/demo/src/lib.rs",
            "pub fn value() -> u8 { 1 }\n",
        );

        let original_hash = sha256_file(&target).expect("original hash");

        let request = PrivatePatchRequest {
            schema: PRIVATE_PATCH_SCHEMA.into(),
            request_id: "request-roundtrip".into(),
            actor: "chappy".into(),
            reason: "verify Private VertexHub patch transaction".into(),
            relative_path: "crates/demo/src/lib.rs".into(),
            expected_sha256: original_hash.clone(),
            replacement_content: "pub fn value() -> u8 { 2 }\n".into(),
        };

        let preview = stage_private_patch(&workspace, &control, &request).expect("stage patch");

        assert!(preview.ready);
        assert!(preview.human_gate_required);
        assert_eq!(preview.current_sha256, original_hash);

        let receipt = apply_staged_private_patch(
            &workspace,
            &control,
            &request.request_id,
            &HumanApproval {
                request_id: request.request_id.clone(),
                approved: true,
                approved_by: "human-gate".into(),
            },
        )
        .expect("apply patch");

        let applied = read_private_source_snapshot(&workspace, "crates/demo/src/lib.rs")
            .expect("read applied");

        assert_eq!(applied.content, "pub fn value() -> u8 { 2 }\n");
        assert_eq!(applied.sha256, receipt.applied_sha256);

        let restored =
            rollback_private_patch(&workspace, &control, &receipt, "human-gate").expect("rollback");

        assert_eq!(restored.content, "pub fn value() -> u8 { 1 }\n");
        assert_eq!(restored.sha256, original_hash);

        let _ = fs::remove_dir_all(workspace);
        let _ = fs::remove_dir_all(control);
    }
}
