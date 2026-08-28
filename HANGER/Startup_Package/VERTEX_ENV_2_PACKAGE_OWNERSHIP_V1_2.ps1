#requires -Version 7.0
<#
VERTEX ENV-2 V1.2
PACKAGE OWNERSHIP / INSTALL RECEIPT / ROLLBACK FOUNDATION

Purpose:
  Register only filesystem assets explicitly described by an ENV-2 manifest.
  Never infer ownership from mere existence.
  Never delete, overwrite, mutate registry/services/firewall/PATH/drivers.

Modes:
  Audit   : read-only ownership evaluation
  Register: write ownership ledger only; requires explicit approval

Approval token:
  APPROVE-OWNERSHIP
#>

param(
    [ValidateSet('Audit','Register')]
    [string]$Mode = 'Audit',

    [string]$Approval = '',

    [string]$ManifestPath = '',

    [string]$ExecutionReceiptPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RequiredApproval = 'APPROVE-OWNERSHIP'
$LedgerSchema = 'vertex.environment.ownership-ledger.v1'
$RecordSchema = 'vertex.environment.ownership-record.v1'

function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $Default }
    return $p.Value
}

function Get-Sha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Resolve-ReportRoot {
    $candidates = @(
        'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports',
        (Join-Path $PSScriptRoot '_vertex_reports')
    )
    $root = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -First 1
    if (-not $root) {
        $root = Join-Path $PSScriptRoot '_vertex_reports'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    return $root
}

function Resolve-Latest {
    param([string]$Root,[string]$Filter,[string]$Explicit)
    if (-not [string]::IsNullOrWhiteSpace($Explicit)) {
        if (-not (Test-Path -LiteralPath $Explicit -PathType Leaf)) {
            throw "File not found: $Explicit"
        }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }
    $f = Get-ChildItem -LiteralPath $Root -Filter $Filter -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $f) { throw "No file matching '$Filter' in $Root" }
    return $f.FullName
}

function Normalize-PathString {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    try { return [IO.Path]::GetFullPath($Path).TrimEnd('\') }
    catch { return $Path.TrimEnd('\') }
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V1.2 — PACKAGE OWNERSHIP FOUNDATION' -ForegroundColor Magenta
Write-Host ' AUDIT -> OWNERSHIP EVIDENCE -> LEDGER' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$reportRoot = Resolve-ReportRoot
$manifestPathResolved = Resolve-Latest -Root $PSScriptRoot -Filter 'VERTEX_ENV_2_PACKAGE_MANIFEST*.json' -Explicit $ManifestPath
$receiptPathResolved = Resolve-Latest -Root $reportRoot -Filter 'VERTEX_ENV2_RECEIPT.*.json' -Explicit $ExecutionReceiptPath

$manifest = Get-Content -LiteralPath $manifestPathResolved -Raw -Encoding utf8 | ConvertFrom-Json
$receipt = Get-Content -LiteralPath $receiptPathResolved -Raw -Encoding utf8 | ConvertFrom-Json

if ([string](Get-Prop $manifest 'schema' '') -ne 'vertex.environment.package-manifest.v1') {
    throw 'Unsupported manifest schema.'
}

if ([string](Get-Prop $receipt 'status' '') -ne 'EXECUTED_GREEN') {
    throw "Ownership registration requires EXECUTED_GREEN receipt."
}

$manifestHash = Get-Sha256 $manifestPathResolved
$receiptManifestHash = [string](Get-Prop $receipt 'manifest_sha256' '')

if ($manifestHash -ne $receiptManifestHash) {
    throw 'Manifest/receipt SHA256 mismatch. Refusing ownership attribution.'
}

$packageId = [string](Get-Prop $manifest 'package_id' 'UNKNOWN')
$receiptPackageId = [string](Get-Prop $receipt 'package_id' 'UNKNOWN')

if ($packageId -ne $receiptPackageId) {
    throw 'Package ID mismatch between manifest and receipt.'
}

if ($Mode -eq 'Register' -and $Approval -ne $RequiredApproval) {
    throw "HUMAN GATE RED: Register requires -Approval $RequiredApproval"
}

$ledgerRoot = Join-Path $reportRoot '_ownership'
$ledgerPath = Join-Path $ledgerRoot 'VERTEX_PACKAGE_OWNERSHIP_LEDGER.json'

$existingLedger = $null
if (Test-Path -LiteralPath $ledgerPath -PathType Leaf) {
    $existingLedger = Get-Content -LiteralPath $ledgerPath -Raw -Encoding utf8 | ConvertFrom-Json
}

$existingRecords = @()
if ($existingLedger) {
    $existingRecords = @(Get-Prop $existingLedger 'records' @())
}

$receiptOps = @(Get-Prop $receipt 'operations' @())
$records = @()
$index = 0

foreach ($op in $receiptOps) {
    $index++
    $type = [string](Get-Prop $op 'type' '')
    $destination = Normalize-PathString ([string](Get-Prop $op 'destination' ''))
    $status = [string](Get-Prop $op 'status' '')
    $before = Get-Prop $op 'before'
    $after = Get-Prop $op 'after'

    if ($status -ne 'EXECUTED') {
        throw "Operation $index is not EXECUTED."
    }

    $preExisting = $false
    if ($type -eq 'ensure_directory') {
        $preExisting = [bool](Get-Prop $before 'existed' $false)
    } else {
        $preExisting = [bool](Get-Prop $before 'destination_existed' $false)
    }

    $existsNow = Test-Path -LiteralPath $destination
    $assetType = switch ($type) {
        'ensure_directory' { 'directory' }
        'copy_file'        { 'file' }
        'copy_tree'        { 'directory_tree' }
        default            { 'unknown' }
    }

    # Critical rule:
    # existence alone NEVER grants Vertex ownership.
    # Vertex ownership is granted only when the receipt proves ENV-2 created
    # an asset that did not exist before execution.
    $ownership = if (-not $preExisting -and $existsNow) {
        'VERTEX_CREATED'
    } elseif ($preExisting) {
        'PRE_EXISTING_NOT_OWNED'
    } else {
        'UNVERIFIED'
    }

    $rollbackEligible = ($ownership -eq 'VERTEX_CREATED')
    $currentHash = if ($assetType -eq 'file') { Get-Sha256 $destination } else { $null }

    $conflict = $existingRecords | Where-Object {
        (Normalize-PathString ([string](Get-Prop $_ 'path' ''))) -ieq $destination -and
        [string](Get-Prop $_ 'package_id' '') -ne $packageId
    } | Select-Object -First 1

    if ($conflict) {
        $ownership = 'CONFLICT'
        $rollbackEligible = $false
    }

    $records += [pscustomobject][ordered]@{
        schema = $RecordSchema
        package_id = $packageId
        execution_id = [string](Get-Prop $receipt 'execution_id' '')
        operation_index = $index
        operation_type = $type
        asset_type = $assetType
        path = $destination
        existed_before = $preExisting
        exists_after = $existsNow
        ownership = $ownership
        rollback_eligible = $rollbackEligible
        sha256 = $currentHash
        registered_at = (Get-Date).ToString('o')
        source_manifest = $manifestPathResolved
        source_manifest_sha256 = $manifestHash
        source_receipt = $receiptPathResolved
        source_receipt_sha256 = Get-Sha256 $receiptPathResolved
    }
}

Write-Host ("Mode       : {0}" -f $Mode) -ForegroundColor Green
Write-Host ("Package    : {0}" -f $packageId) -ForegroundColor Green
Write-Host ("Receipt    : {0}" -f $receiptPathResolved) -ForegroundColor Green
Write-Host ("Assets     : {0}" -f $records.Count) -ForegroundColor Green
Write-Host ''

foreach ($r in $records) {
    $color = switch ($r.ownership) {
        'VERTEX_CREATED' { 'Green' }
        'PRE_EXISTING_NOT_OWNED' { 'Yellow' }
        'CONFLICT' { 'Red' }
        default { 'DarkYellow' }
    }
    Write-Host ("[{0}] {1}" -f $r.ownership, $r.path) -ForegroundColor $color
    Write-Host ("    rollback_eligible : {0}" -f $r.rollback_eligible)
}

if ($records | Where-Object { $_.ownership -in @('CONFLICT','UNVERIFIED') }) {
    throw 'OWNERSHIP AUDIT RED: conflict or unverifiable asset detected.'
}

if ($Mode -eq 'Register') {
    New-Item -ItemType Directory -Path $ledgerRoot -Force | Out-Null

    $merged = @($existingRecords)
    foreach ($record in $records) {
        # Replace only the same package/path record. Never claim another package's asset.
        $merged = @($merged | Where-Object {
            -not (
                [string](Get-Prop $_ 'package_id' '') -eq $record.package_id -and
                (Normalize-PathString ([string](Get-Prop $_ 'path' ''))) -ieq $record.path
            )
        })
        $merged += $record
    }

    $ledger = [ordered]@{
        schema = $LedgerSchema
        updated_at = (Get-Date).ToString('o')
        records = $merged
    }

    $ledger | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ledgerPath -Encoding utf8
    Write-Host ''
    Write-Host 'OWNERSHIP LEDGER : REGISTERED' -ForegroundColor Green
    Write-Host ("Ledger           : {0}" -f $ledgerPath) -ForegroundColor Green
} else {
    Write-Host ''
    Write-Host 'OWNERSHIP LEDGER : AUDIT ONLY / NO WRITE' -ForegroundColor Green
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' SAFETY' -ForegroundColor Magenta
Write-Host '  Filesystem delete : DENIED'
Write-Host '  Overwrite         : DENIED'
Write-Host '  Registry          : DENIED'
Write-Host '  Services          : DENIED'
Write-Host '  Firewall          : DENIED'
Write-Host '  PATH / Env        : DENIED'
Write-Host '  Drivers           : DENIED'
Write-Host '============================================================' -ForegroundColor Magenta
