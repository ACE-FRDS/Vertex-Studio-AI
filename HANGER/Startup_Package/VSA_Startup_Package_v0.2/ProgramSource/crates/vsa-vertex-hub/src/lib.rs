use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Component, Path, PathBuf};

pub const HUB_PACKAGE_SCHEMA: &str = "vertex.hub.package.v1";
pub const HUB_REGISTRY_SCHEMA: &str = "vertex.hub.registry.v1";

#[derive(Debug, Deserialize)]
pub struct HubPackageFile {
    pub path: String,
    pub sha256: String,
    pub bytes: u64,
}

#[derive(Debug, Deserialize)]
pub struct HubPackageManifest {
    pub schema: String,
    pub package_id: String,
    pub version: String,
    pub files: Vec<HubPackageFile>,
}

#[derive(Debug, Deserialize)]
pub struct HubRegistryEntry {
    pub package_id: String,
    pub version: String,
    pub status: String,
    pub manifest: String,
    pub manifest_sha256: String,
}

#[derive(Debug, Deserialize)]
pub struct HubRegistry {
    pub schema: String,
    pub packages: Vec<HubRegistryEntry>,
}

#[derive(Debug)]
pub struct PackageValidation {
    pub package_id: String,
    pub version: String,
    pub file_count: usize,
}

fn safe_relative(value: &str) -> Result<PathBuf, String> {
    let path = Path::new(value);

    if path.as_os_str().is_empty() || path.is_absolute() {
        return Err(format!("unsafe Hub path: {value}"));
    }

    for component in path.components() {
        match component {
            Component::Normal(_) | Component::CurDir => {}
            _ => return Err(format!("unsafe Hub path component: {value}")),
        }
    }

    Ok(path.to_path_buf())
}

fn sha256_file(path: &Path) -> Result<String, String> {
    let bytes =
        fs::read(path).map_err(|error| format!("cannot read {}: {error}", path.display()))?;

    let digest = Sha256::digest(bytes);
    Ok(digest.iter().map(|byte| format!("{byte:02x}")).collect())
}

pub fn validate_package_dir(package_root: &Path) -> Result<PackageValidation, String> {
    let manifest_path = package_root.join("manifest.json");
    let manifest: HubPackageManifest = serde_json::from_slice(
        &fs::read(&manifest_path)
            .map_err(|error| format!("cannot read {}: {error}", manifest_path.display()))?,
    )
    .map_err(|error| format!("invalid Hub manifest JSON: {error}"))?;

    if manifest.schema != HUB_PACKAGE_SCHEMA {
        return Err(format!(
            "unsupported Hub package schema: {}",
            manifest.schema
        ));
    }

    for file in &manifest.files {
        let relative = safe_relative(&file.path)?;
        let full = package_root.join(relative);

        let metadata = fs::metadata(&full)
            .map_err(|error| format!("package file missing {}: {error}", full.display()))?;

        if metadata.len() != file.bytes {
            return Err(format!(
                "package file size mismatch {}: manifest={} actual={}",
                full.display(),
                file.bytes,
                metadata.len()
            ));
        }

        let actual = sha256_file(&full)?;
        if actual != file.sha256.to_ascii_lowercase() {
            return Err(format!("package SHA-256 mismatch: {}", full.display()));
        }
    }

    Ok(PackageValidation {
        package_id: manifest.package_id,
        version: manifest.version,
        file_count: manifest.files.len(),
    })
}

pub fn validate_registry(hub_root: &Path) -> Result<Vec<PackageValidation>, String> {
    let registry_path = hub_root.join("registry.json");
    let registry: HubRegistry = serde_json::from_slice(
        &fs::read(&registry_path)
            .map_err(|error| format!("cannot read {}: {error}", registry_path.display()))?,
    )
    .map_err(|error| format!("invalid Hub registry JSON: {error}"))?;

    if registry.schema != HUB_REGISTRY_SCHEMA {
        return Err(format!(
            "unsupported Hub registry schema: {}",
            registry.schema
        ));
    }

    let mut reports = Vec::new();

    for entry in registry.packages {
        if entry.status != "registered" {
            return Err(format!(
                "Hub package is not registered: {}@{}",
                entry.package_id, entry.version
            ));
        }

        let manifest_rel = safe_relative(&entry.manifest)?;
        let manifest_path = hub_root.join(&manifest_rel);

        let actual_manifest_hash = sha256_file(&manifest_path)?;
        if actual_manifest_hash != entry.manifest_sha256.to_ascii_lowercase() {
            return Err(format!(
                "Hub manifest SHA-256 mismatch: {}@{}",
                entry.package_id, entry.version
            ));
        }

        let package_root = manifest_path
            .parent()
            .ok_or_else(|| format!("manifest has no package root: {}", manifest_path.display()))?;

        let report = validate_package_dir(package_root)?;

        if report.package_id != entry.package_id || report.version != entry.version {
            return Err(format!(
                "Hub registry identity mismatch: {}@{}",
                entry.package_id, entry.version
            ));
        }

        reports.push(report);
    }

    Ok(reports)
}

#[cfg(test)]
mod tests {
    use super::safe_relative;

    #[test]
    fn hub_path_traversal_is_denied() {
        assert!(safe_relative("../secret").is_err());
        assert!(safe_relative("/absolute").is_err());
        assert!(safe_relative("contracts/live-session.json").is_ok());
    }
}
// VERTEX HUB INSTALLER V1
pub fn install_registered_package(
    hub_root: &Path,
    install_root: &Path,
    package_id: &str,
    version: &str,
) -> Result<PackageValidation, String> {
    let registry_path = hub_root.join("registry.json");
    let registry: HubRegistry = serde_json::from_slice(
        &fs::read(&registry_path)
            .map_err(|error| format!("cannot read {}: {error}", registry_path.display()))?,
    )
    .map_err(|error| format!("invalid Hub registry JSON: {error}"))?;

    if registry.schema != HUB_REGISTRY_SCHEMA {
        return Err(format!(
            "unsupported Hub registry schema: {}",
            registry.schema
        ));
    }

    let entry = registry
        .packages
        .iter()
        .find(|entry| entry.package_id == package_id && entry.version == version)
        .ok_or_else(|| format!("Hub package is not registered: {package_id}@{version}"))?;

    if entry.status != "registered" {
        return Err(format!(
            "Hub package is not installable: {package_id}@{version}"
        ));
    }

    let manifest_rel = safe_relative(&entry.manifest)?;
    let source_manifest = hub_root.join(&manifest_rel);

    let actual_manifest_hash = sha256_file(&source_manifest)?;
    if actual_manifest_hash != entry.manifest_sha256.to_ascii_lowercase() {
        return Err(format!(
            "Hub manifest hash mismatch: {package_id}@{version}"
        ));
    }

    let source_root = source_manifest
        .parent()
        .ok_or_else(|| format!("invalid source package root: {}", source_manifest.display()))?;

    let validated = validate_package_dir(source_root)?;

    if validated.package_id != package_id || validated.version != version {
        return Err(format!(
            "Hub package identity mismatch: requested={package_id}@{version} actual={}@{}",
            validated.package_id, validated.version
        ));
    }

    let manifest: HubPackageManifest = serde_json::from_slice(
        &fs::read(&source_manifest)
            .map_err(|error| format!("cannot read {}: {error}", source_manifest.display()))?,
    )
    .map_err(|error| format!("invalid Hub manifest JSON: {error}"))?;

    if install_root.exists() {
        return Err(format!(
            "Hub install destination already exists: {}",
            install_root.display()
        ));
    }

    fs::create_dir_all(install_root)
        .map_err(|error| format!("cannot create {}: {error}", install_root.display()))?;

    let rollback = || {
        let _ = fs::remove_dir_all(install_root);
    };

    for file in &manifest.files {
        let relative = match safe_relative(&file.path) {
            Ok(path) => path,
            Err(error) => {
                rollback();
                return Err(error);
            }
        };

        let source = source_root.join(&relative);
        let destination = install_root.join(&relative);

        if let Some(parent) = destination.parent() {
            if let Err(error) = fs::create_dir_all(parent) {
                rollback();
                return Err(format!("cannot create {}: {error}", parent.display()));
            }
        }

        if let Err(error) = fs::copy(&source, &destination) {
            rollback();
            return Err(format!(
                "cannot install {} -> {}: {error}",
                source.display(),
                destination.display()
            ));
        }
    }

    if let Err(error) = fs::copy(&source_manifest, install_root.join("manifest.json")) {
        rollback();
        return Err(format!("cannot install manifest: {error}"));
    }

    match validate_package_dir(install_root) {
        Ok(report) => Ok(report),
        Err(error) => {
            rollback();
            Err(format!(
                "installed Hub package failed integrity check: {error}"
            ))
        }
    }
}
// END VERTEX HUB INSTALLER V1

// VERTEX HUB RUNTIME EQUIPMENT V1
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HubRuntimePackage {
    pub package_id: String,
    pub version: String,
    pub enabled: bool,
    pub installed_at_ms: u128,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct HubRuntimeState {
    pub schema: String,
    pub packages: Vec<HubRuntimePackage>,
}

#[derive(Debug, Clone, Serialize)]
pub struct HubRuntimeMutation {
    pub package_id: String,
    pub version: String,
    pub installed: bool,
    pub enabled: bool,
}

fn hub_identity(value: &str, label: &str) -> Result<(), String> {
    if value.is_empty()
        || !value
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || "._-".contains(character))
    {
        return Err(format!("unsafe Hub {label}: {value}"));
    }

    Ok(())
}

fn hub_now_ms() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

fn hub_state_path(runtime_root: &Path) -> PathBuf {
    runtime_root.join("state.json")
}

fn hub_audit_path(runtime_root: &Path) -> PathBuf {
    runtime_root.join("audit.ndjson")
}

fn hub_installed_root(runtime_root: &Path) -> PathBuf {
    runtime_root.join("installed")
}

pub fn load_hub_runtime_state(runtime_root: &Path) -> Result<HubRuntimeState, String> {
    let path = hub_state_path(runtime_root);

    if !path.exists() {
        return Ok(HubRuntimeState {
            schema: "vertex.hub.runtime-state.v1".to_string(),
            packages: Vec::new(),
        });
    }

    let state: HubRuntimeState = serde_json::from_slice(
        &fs::read(&path).map_err(|error| format!("cannot read {}: {error}", path.display()))?,
    )
    .map_err(|error| format!("invalid Hub runtime state JSON: {error}"))?;

    if state.schema != "vertex.hub.runtime-state.v1" {
        return Err(format!(
            "unsupported Hub runtime state schema: {}",
            state.schema
        ));
    }

    Ok(state)
}

fn save_hub_runtime_state(runtime_root: &Path, state: &HubRuntimeState) -> Result<(), String> {
    fs::create_dir_all(runtime_root)
        .map_err(|error| format!("cannot create {}: {error}", runtime_root.display()))?;

    let path = hub_state_path(runtime_root);
    let temp = runtime_root.join("state.json.tmp");

    let bytes = serde_json::to_vec_pretty(state)
        .map_err(|error| format!("cannot serialize Hub runtime state: {error}"))?;

    fs::write(&temp, bytes).map_err(|error| format!("cannot write {}: {error}", temp.display()))?;

    if path.exists() {
        fs::remove_file(&path)
            .map_err(|error| format!("cannot replace {}: {error}", path.display()))?;
    }

    fs::rename(&temp, &path).map_err(|error| format!("cannot commit {}: {error}", path.display()))
}

fn append_hub_audit(
    runtime_root: &Path,
    action: &str,
    package_id: &str,
    version: &str,
) -> Result<(), String> {
    use std::io::Write;

    fs::create_dir_all(runtime_root)
        .map_err(|error| format!("cannot create {}: {error}", runtime_root.display()))?;

    let path = hub_audit_path(runtime_root);
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .map_err(|error| format!("cannot open {}: {error}", path.display()))?;

    let line = serde_json::json!({
        "schema": "vertex.hub.audit.v1",
        "timestamp_ms": hub_now_ms(),
        "action": action,
        "package_id": package_id,
        "version": version
    });

    writeln!(file, "{line}").map_err(|error| format!("cannot append {}: {error}", path.display()))
}

fn hub_runtime_package_dir(
    runtime_root: &Path,
    package_id: &str,
    version: &str,
) -> Result<PathBuf, String> {
    hub_identity(package_id, "package_id")?;
    hub_identity(version, "version")?;

    Ok(hub_installed_root(runtime_root)
        .join(package_id)
        .join(version))
}

fn runtime_mutation(
    state: &HubRuntimeState,
    package_id: &str,
    version: &str,
) -> HubRuntimeMutation {
    let package = state
        .packages
        .iter()
        .find(|package| package.package_id == package_id && package.version == version);

    HubRuntimeMutation {
        package_id: package_id.to_string(),
        version: version.to_string(),
        installed: package.is_some(),
        enabled: package.is_some_and(|package| package.enabled),
    }
}

pub fn hub_runtime_install(
    hub_root: &Path,
    runtime_root: &Path,
    package_id: &str,
    version: &str,
) -> Result<HubRuntimeMutation, String> {
    let destination = hub_runtime_package_dir(runtime_root, package_id, version)?;

    if destination.exists() {
        let validation = validate_package_dir(&destination)?;

        if validation.package_id != package_id || validation.version != version {
            return Err(format!(
                "installed Hub package identity mismatch: {}@{}",
                validation.package_id, validation.version
            ));
        }
    } else {
        install_registered_package(hub_root, &destination, package_id, version)?;
    }

    let mut state = load_hub_runtime_state(runtime_root)?;

    if !state
        .packages
        .iter()
        .any(|package| package.package_id == package_id && package.version == version)
    {
        state.packages.push(HubRuntimePackage {
            package_id: package_id.to_string(),
            version: version.to_string(),
            enabled: false,
            installed_at_ms: hub_now_ms(),
        });
    }

    save_hub_runtime_state(runtime_root, &state)?;
    append_hub_audit(runtime_root, "INSTALL", package_id, version)?;

    Ok(runtime_mutation(&state, package_id, version))
}

pub fn hub_runtime_set_enabled(
    runtime_root: &Path,
    package_id: &str,
    version: &str,
    enabled: bool,
) -> Result<HubRuntimeMutation, String> {
    hub_identity(package_id, "package_id")?;
    hub_identity(version, "version")?;

    let destination = hub_runtime_package_dir(runtime_root, package_id, version)?;
    validate_package_dir(&destination)?;

    let mut state = load_hub_runtime_state(runtime_root)?;
    let package = state
        .packages
        .iter_mut()
        .find(|package| package.package_id == package_id && package.version == version)
        .ok_or_else(|| format!("Hub package is not installed: {package_id}@{version}"))?;

    package.enabled = enabled;

    save_hub_runtime_state(runtime_root, &state)?;
    append_hub_audit(
        runtime_root,
        if enabled { "ENABLE" } else { "DISABLE" },
        package_id,
        version,
    )?;

    Ok(runtime_mutation(&state, package_id, version))
}

pub fn hub_runtime_uninstall(
    runtime_root: &Path,
    package_id: &str,
    version: &str,
) -> Result<HubRuntimeMutation, String> {
    let destination = hub_runtime_package_dir(runtime_root, package_id, version)?;

    if destination.exists() {
        validate_package_dir(&destination)?;

        fs::remove_dir_all(&destination)
            .map_err(|error| format!("cannot uninstall {}: {error}", destination.display()))?;
    }

    let mut state = load_hub_runtime_state(runtime_root)?;
    state
        .packages
        .retain(|package| !(package.package_id == package_id && package.version == version));

    save_hub_runtime_state(runtime_root, &state)?;
    append_hub_audit(runtime_root, "UNINSTALL", package_id, version)?;

    Ok(runtime_mutation(&state, package_id, version))
}
// END VERTEX HUB RUNTIME EQUIPMENT V1

pub mod private_control;

pub mod private_transport;
