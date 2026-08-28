$ErrorActionPreference = 'Stop'

$workspace = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource'
$hub       = Join-Path $workspace 'crates\vsa-vertex-hub'
$lib       = Join-Path $hub 'src\lib.rs'
$transport = Join-Path $hub 'src\private_transport.rs'
$binDir    = Join-Path $hub 'src\bin'
$cli       = Join-Path $binDir 'private_hub.rs'
$toolDir   = 'G:\Vertex_Project\Vertex_Studio_AI\Gateway\tools'
$wrapper   = Join-Path $toolDir 'Invoke-PrivateVertexHub.ps1'

$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = "G:\Vertex_Project\Vertex_Studio_AI\Gateway\backups\private-vertexhub-v0.2-$stamp"

Write-Host ''
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ' PRIVATE VERTEXHUB v0.2 - LOCAL PATCH TRANSPORT' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan

if (-not (Test-Path $lib)) {
    throw "Hub lib.rs not found: $lib"
}
if (-not (Test-Path (Join-Path $hub 'src\private_control.rs'))) {
    throw 'Private VertexHub v0.1 private_control.rs is missing.'
}
if (Test-Path $transport) {
    throw "private_transport.rs already exists; refusing to overwrite: $transport"
}
if (Test-Path $cli) {
    throw "private_hub CLI already exists; refusing to overwrite: $cli"
}

New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
Copy-Item $lib (Join-Path $backupDir 'lib.rs') -Force

if (Test-Path $wrapper) {
    Copy-Item $wrapper (Join-Path $backupDir 'Invoke-PrivateVertexHub.ps1') -Force
}

$transportText = @'
use crate::private_control::{
    read_private_source_snapshot, stage_private_patch, PrivatePatchPreview, PrivatePatchRequest,
    PRIVATE_PATCH_SCHEMA,
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
        apply_staged_private_patch, read_private_source_snapshot, HumanApproval,
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

        let error =
            stage_private_text_patch(&workspace, &control, &request).expect_err("must reject count");

        assert!(error.contains("occurrence mismatch"));

        let _ = fs::remove_dir_all(workspace);
        let _ = fs::remove_dir_all(control);
    }
}
'@

$cliText = @'
use std::env;
use std::fs;
use std::path::Path;

use vsa_vertex_hub::private_control::{
    apply_staged_private_patch, read_private_source_snapshot, rollback_private_patch, HumanApproval,
    PrivatePatchReceipt,
};
use vsa_vertex_hub::private_transport::{
    stage_private_text_patch, PrivateTextPatchRequest,
};

fn usage() -> ! {
    eprintln!(
        "Private VertexHub CLI v0.2\n\
         \n\
         Commands:\n\
         snapshot <workspace_root> <relative_path>\n\
         stage-text <workspace_root> <control_root> <request.json>\n\
         apply <workspace_root> <control_root> <request_id> <approved_by>\n\
         rollback <workspace_root> <control_root> <receipt.json> <approved_by>"
    );
    std::process::exit(2);
}

fn print_json<T: serde::Serialize>(value: &T) -> Result<(), String> {
    let json = serde_json::to_string_pretty(value)
        .map_err(|error| format!("cannot serialize CLI output: {error}"))?;
    println!("{json}");
    Ok(())
}

fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().collect();

    let Some(command) = args.get(1).map(String::as_str) else {
        usage();
    };

    match command {
        "snapshot" => {
            if args.len() != 4 {
                usage();
            }

            let snapshot = read_private_source_snapshot(Path::new(&args[2]), &args[3])?;
            print_json(&snapshot)
        }
        "stage-text" => {
            if args.len() != 5 {
                usage();
            }

            let bytes = fs::read(&args[4])
                .map_err(|error| format!("cannot read patch request {}: {error}", args[4]))?;

            let request: PrivateTextPatchRequest = serde_json::from_slice(&bytes)
                .map_err(|error| format!("invalid Private VertexHub text-patch JSON: {error}"))?;

            let preview =
                stage_private_text_patch(Path::new(&args[2]), Path::new(&args[3]), &request)?;

            print_json(&preview)
        }
        "apply" => {
            if args.len() != 6 {
                usage();
            }

            let approval = HumanApproval {
                request_id: args[4].clone(),
                approved: true,
                approved_by: args[5].clone(),
            };

            let receipt = apply_staged_private_patch(
                Path::new(&args[2]),
                Path::new(&args[3]),
                &args[4],
                &approval,
            )?;

            print_json(&receipt)
        }
        "rollback" => {
            if args.len() != 6 {
                usage();
            }

            let bytes = fs::read(&args[4])
                .map_err(|error| format!("cannot read receipt {}: {error}", args[4]))?;

            let receipt: PrivatePatchReceipt = serde_json::from_slice(&bytes)
                .map_err(|error| format!("invalid Private VertexHub receipt JSON: {error}"))?;

            let snapshot = rollback_private_patch(
                Path::new(&args[2]),
                Path::new(&args[3]),
                &receipt,
                &args[5],
            )?;

            print_json(&snapshot)
        }
        _ => usage(),
    }
}

fn main() {
    if let Err(error) = run() {
        eprintln!("PRIVATE_VERTEXHUB_ERROR: {error}");
        std::process::exit(1);
    }
}
'@

$wrapperText = @'
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Snapshot', 'StageText', 'Apply', 'Rollback')]
    [string]$Action,

    [string]$RelativePath,
    [string]$RequestFile,
    [string]$RequestId,
    [string]$ReceiptFile,
    [string]$ApprovedBy
)

$ErrorActionPreference = 'Stop'

$Workspace = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource'
$ControlRoot = 'G:\Vertex_Project\Vertex_Studio_AI\Gateway\private-hub'

Set-Location $Workspace

switch ($Action) {
    'Snapshot' {
        if ([string]::IsNullOrWhiteSpace($RelativePath)) {
            throw '-RelativePath is required for Snapshot.'
        }

        & cargo run -q -p vsa-vertex-hub --bin private_hub -- `
            snapshot $Workspace $RelativePath

        if ($LASTEXITCODE -ne 0) {
            throw "Private VertexHub Snapshot failed with exit code $LASTEXITCODE"
        }
    }

    'StageText' {
        if ([string]::IsNullOrWhiteSpace($RequestFile)) {
            throw '-RequestFile is required for StageText.'
        }

        $resolved = (Resolve-Path $RequestFile).Path

        & cargo run -q -p vsa-vertex-hub --bin private_hub -- `
            stage-text $Workspace $ControlRoot $resolved

        if ($LASTEXITCODE -ne 0) {
            throw "Private VertexHub StageText failed with exit code $LASTEXITCODE"
        }
    }

    'Apply' {
        if ([string]::IsNullOrWhiteSpace($RequestId)) {
            throw '-RequestId is required for Apply.'
        }

        if ([string]::IsNullOrWhiteSpace($ApprovedBy)) {
            throw '-ApprovedBy is required for Apply. Human Gate cannot be implicit.'
        }

        & cargo run -q -p vsa-vertex-hub --bin private_hub -- `
            apply $Workspace $ControlRoot $RequestId $ApprovedBy

        if ($LASTEXITCODE -ne 0) {
            throw "Private VertexHub Apply failed with exit code $LASTEXITCODE"
        }
    }

    'Rollback' {
        if ([string]::IsNullOrWhiteSpace($ReceiptFile)) {
            throw '-ReceiptFile is required for Rollback.'
        }

        if ([string]::IsNullOrWhiteSpace($ApprovedBy)) {
            throw '-ApprovedBy is required for Rollback. Human Gate cannot be implicit.'
        }

        $resolved = (Resolve-Path $ReceiptFile).Path

        & cargo run -q -p vsa-vertex-hub --bin private_hub -- `
            rollback $Workspace $ControlRoot $resolved $ApprovedBy

        if ($LASTEXITCODE -ne 0) {
            throw "Private VertexHub Rollback failed with exit code $LASTEXITCODE"
        }
    }
}
'@

try {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    New-Item -ItemType Directory -Path $toolDir -Force | Out-Null

    Set-Content -Path $transport -Value $transportText -Encoding utf8
    Set-Content -Path $cli       -Value $cliText       -Encoding utf8
    Set-Content -Path $wrapper   -Value $wrapperText   -Encoding utf8

    $libText = Get-Content -Path $lib -Raw

    if ($libText -notmatch '(?m)^\s*pub\s+mod\s+private_transport\s*;') {
        Add-Content -Path $lib -Value "`r`npub mod private_transport;" -Encoding utf8
    }

    Set-Location $workspace

    Write-Host ''
    Write-Host '[1/3] cargo fmt -p vsa-vertex-hub' -ForegroundColor Yellow
    & cargo fmt -p vsa-vertex-hub
    if ($LASTEXITCODE -ne 0) {
        throw "cargo fmt failed with exit code $LASTEXITCODE"
    }

    Write-Host ''
    Write-Host '[2/3] cargo check -p vsa-vertex-hub' -ForegroundColor Yellow
    & cargo check -p vsa-vertex-hub
    if ($LASTEXITCODE -ne 0) {
        throw "cargo check failed with exit code $LASTEXITCODE"
    }

    Write-Host ''
    Write-Host '[3/3] cargo test -p vsa-vertex-hub' -ForegroundColor Yellow
    & cargo test -p vsa-vertex-hub
    if ($LASTEXITCODE -ne 0) {
        throw "cargo test failed with exit code $LASTEXITCODE"
    }

    Write-Host ''
    Write-Host '==================================================' -ForegroundColor Green
    Write-Host ' PRIVATE VERTEXHUB v0.2 LOCAL TRANSPORT INSTALLED' -ForegroundColor Green
    Write-Host '==================================================' -ForegroundColor Green
    Write-Host "Transport : $transport"
    Write-Host "CLI       : $cli"
    Write-Host "Wrapper   : $wrapper"
    Write-Host "Backup    : $backupDir"
    Write-Host ''
    Write-Host 'Capabilities:' -ForegroundColor Cyan
    Write-Host '  COMPACT TEXT PATCH : READY'
    Write-Host '  OCCURRENCE LOCK    : READY'
    Write-Host '  SHA256 LOCK        : READY'
    Write-Host '  LOCAL CLI          : READY'
    Write-Host '  HUMAN APPLY        : READY'
    Write-Host '  ROLLBACK           : READY'
    Write-Host '  NETWORK WRITE      : DISABLED'
    Write-Host ''
    Write-Host 'Smoke command:' -ForegroundColor Yellow
    Write-Host "& '$wrapper' -Action Snapshot -RelativePath 'crates\vsa-vertex-hub\Cargo.toml'"
}
catch {
    Write-Host ''
    Write-Host 'INSTALL FAILED - ROLLING BACK' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    Copy-Item (Join-Path $backupDir 'lib.rs') $lib -Force

    if (Test-Path $transport) {
        Remove-Item $transport -Force
    }

    if (Test-Path $cli) {
        Remove-Item $cli -Force
    }

    if (Test-Path (Join-Path $backupDir 'Invoke-PrivateVertexHub.ps1')) {
        Copy-Item (Join-Path $backupDir 'Invoke-PrivateVertexHub.ps1') $wrapper -Force
    }
    elseif (Test-Path $wrapper) {
        Remove-Item $wrapper -Force
    }

    Write-Host "Rollback complete. Backup preserved at: $backupDir" -ForegroundColor Yellow
    throw
}
