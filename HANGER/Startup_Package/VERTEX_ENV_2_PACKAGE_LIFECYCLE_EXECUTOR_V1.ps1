#requires -Version 7.0
<#
VERTEX ENV-2
Package Lifecycle / Deployment Executor V1

DESIGN
  ENV-0 observes.
  ENV-1 plans.
  Human Gate approves.
  ENV-2 executes approved, allow-listed filesystem operations.
  ENV-0 re-surveys and verifies.

V1 SAFETY BOUNDARY
  ALLOWED:
    - ensure_directory
    - copy_file
    - copy_tree

  FORBIDDEN IN V1:
    - Registry mutation
    - Service mutation
    - Firewall mutation
    - PATH/environment mutation
    - Driver mutation
    - Package manager execution
    - Arbitrary shell command execution
    - Deletion / cleaner actions
    - Port binding

DEFAULT MODE
  DryRun

EXECUTION REQUIRES
  -Mode Execute
  -Approval APPROVE-ENV2
#>

param(
    [ValidateSet('DryRun','Execute')]
    [string]$Mode = 'DryRun',

    [string]$Approval = '',

    [string]$ManifestPath = '',

    [string]$PlanPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MissionId = 'VERTEX_ENV_2_PACKAGE_LIFECYCLE_EXECUTOR'
$Schema = 'vertex.environment.execution-receipt.v1'
$RequiredApproval = 'APPROVE-ENV2'

function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }

    return $property.Value
}

function Get-Sha256 {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Resolve-ReportRoot {
    $roots = @(
        'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports',
        'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\_vertex_reports',
        (Join-Path $PSScriptRoot '_vertex_reports')
    )

    $root = $roots |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1

    if (-not $root) {
        $root = Join-Path $PSScriptRoot '_vertex_reports'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }

    return $root
}

function Resolve-LatestPlan {
    param([string]$Root)

    $plan = Get-ChildItem -LiteralPath $Root -Filter 'VERTEX_ENVIRONMENT_PLAN.*.json' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $plan) {
        throw "ENV-2: No VERTEX_ENVIRONMENT_PLAN.*.json found in $Root. Run ENV-1 first."
    }

    return $plan.FullName
}

function Resolve-Manifest {
    param([string]$Requested)

    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        if (-not (Test-Path -LiteralPath $Requested -PathType Leaf)) {
            throw "ENV-2: Manifest not found: $Requested"
        }
        return (Resolve-Path -LiteralPath $Requested).Path
    }

    $default = Join-Path $PSScriptRoot 'VERTEX_ENV_2_PACKAGE_MANIFEST_SAMPLE.json'

    if (-not (Test-Path -LiteralPath $default -PathType Leaf)) {
        throw "ENV-2: No manifest supplied and default manifest not found: $default"
    }

    return $default
}

function Assert-Plan {
    param($Plan)

    $mode = [string](Get-Prop $Plan 'mode' '')
    if ($mode -ne 'READ_ONLY_PLANNING') {
        throw "ENV-2: Unsupported plan mode: $mode"
    }

    $policy = Get-Prop $Plan 'execution_policy'
    $requiresGate = [bool](Get-Prop $policy 'requires_human_gate_before_env2' $true)

    if (-not $requiresGate) {
        throw 'ENV-2: Plan does not explicitly require Human Gate. Refusing to execute.'
    }
}

function Assert-Manifest {
    param($Manifest)

    $schema = [string](Get-Prop $Manifest 'schema' '')
    if ($schema -ne 'vertex.environment.package-manifest.v1') {
        throw "ENV-2: Unsupported manifest schema: $schema"
    }

    $ops = @(Get-Prop $Manifest 'operations' @())

    foreach ($op in $ops) {
        $type = [string](Get-Prop $op 'type' '')

        if ($type -notin @('ensure_directory','copy_file','copy_tree')) {
            throw "ENV-2 V1: Operation '$type' is not allow-listed."
        }
    }
}

function New-OperationReceipt {
    param(
        [int]$Index,
        [string]$Type,
        [string]$Source,
        [string]$Destination
    )

    return [ordered]@{
        index = $Index
        type = $Type
        source = $Source
        destination = $Destination
        status = 'PENDING'
        before = $null
        after = $null
        rollback = $null
        error = $null
    }
}

function Invoke-EnsureDirectory {
    param(
        $Operation,
        [hashtable]$Receipt,
        [bool]$Execute
    )

    $destination = [string](Get-Prop $Operation 'destination' '')
    if ([string]::IsNullOrWhiteSpace($destination)) {
        throw 'ensure_directory requires destination.'
    }

    $existsBefore = Test-Path -LiteralPath $destination -PathType Container
    $Receipt.before = [ordered]@{
        existed = $existsBefore
    }

    if ($Execute -and -not $existsBefore) {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
    }

    $existsAfter = if ($Execute) {
        Test-Path -LiteralPath $destination -PathType Container
    } else {
        $existsBefore
    }

    $Receipt.after = [ordered]@{
        existed = $existsAfter
    }

    $Receipt.rollback = [ordered]@{
        action = if ($existsBefore) { 'NONE' } else { 'REMOVE_DIRECTORY_IF_EMPTY' }
        target = $destination
        executable_in_v1 = $false
    }

    $Receipt.status = if ($Execute) { 'EXECUTED' } else { 'DRY_RUN' }
}

function Invoke-CopyFile {
    param(
        $Operation,
        [hashtable]$Receipt,
        [bool]$Execute
    )

    $source = [string](Get-Prop $Operation 'source' '')
    $destination = [string](Get-Prop $Operation 'destination' '')

    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "copy_file source missing: $source"
    }

    $destExistsBefore = Test-Path -LiteralPath $destination -PathType Leaf

    $Receipt.before = [ordered]@{
        destination_existed = $destExistsBefore
        destination_sha256 = if ($destExistsBefore) { Get-Sha256 $destination } else { $null }
        source_sha256 = Get-Sha256 $source
    }

    if ($Execute) {
        $parent = Split-Path -Parent $destination
        if ($parent) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        if ($destExistsBefore) {
            throw "ENV-2 V1 refuses overwrite: $destination"
        }

        Copy-Item -LiteralPath $source -Destination $destination
    }

    $destExistsAfter = if ($Execute) {
        Test-Path -LiteralPath $destination -PathType Leaf
    } else {
        $destExistsBefore
    }

    $Receipt.after = [ordered]@{
        destination_existed = $destExistsAfter
        destination_sha256 = if ($Execute -and $destExistsAfter) { Get-Sha256 $destination } else { $null }
    }

    $Receipt.rollback = [ordered]@{
        action = if ($destExistsBefore) { 'NONE' } else { 'REMOVE_CREATED_FILE' }
        target = $destination
        executable_in_v1 = $false
    }

    $Receipt.status = if ($Execute) { 'EXECUTED' } else { 'DRY_RUN' }
}

function Invoke-CopyTree {
    param(
        $Operation,
        [hashtable]$Receipt,
        [bool]$Execute
    )

    $source = [string](Get-Prop $Operation 'source' '')
    $destination = [string](Get-Prop $Operation 'destination' '')

    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "copy_tree source missing: $source"
    }

    $destExistsBefore = Test-Path -LiteralPath $destination

    $Receipt.before = [ordered]@{
        destination_existed = $destExistsBefore
    }

    if ($Execute) {
        if ($destExistsBefore) {
            throw "ENV-2 V1 refuses merge/overwrite: $destination"
        }

        $parent = Split-Path -Parent $destination
        if ($parent) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        Copy-Item -LiteralPath $source -Destination $destination -Recurse
    }

    $Receipt.after = [ordered]@{
        destination_existed = if ($Execute) {
            Test-Path -LiteralPath $destination
        } else {
            $destExistsBefore
        }
    }

    $Receipt.rollback = [ordered]@{
        action = if ($destExistsBefore) { 'NONE' } else { 'REMOVE_CREATED_TREE' }
        target = $destination
        executable_in_v1 = $false
    }

    $Receipt.status = if ($Execute) { 'EXECUTED' } else { 'DRY_RUN' }
}

# ------------------------------------------------------------------
# BOOT
# ------------------------------------------------------------------
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 — PACKAGE LIFECYCLE / DEPLOYMENT EXECUTOR V1' -ForegroundColor Magenta
Write-Host ' HUMAN GATE / RECEIPT / ROLLBACK EVIDENCE' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$reportRoot = Resolve-ReportRoot

if ([string]::IsNullOrWhiteSpace($PlanPath)) {
    $PlanPath = Resolve-LatestPlan -Root $reportRoot
} else {
    $PlanPath = (Resolve-Path -LiteralPath $PlanPath).Path
}

$ManifestPath = Resolve-Manifest -Requested $ManifestPath

$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding utf8 | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding utf8 | ConvertFrom-Json

Assert-Plan -Plan $plan
Assert-Manifest -Manifest $manifest

$execute = ($Mode -eq 'Execute')

if ($execute -and $Approval -ne $RequiredApproval) {
    throw "ENV-2 HUMAN GATE RED: Execute requires -Approval $RequiredApproval"
}

Write-Host ("Mode      : {0}" -f $Mode) -ForegroundColor $(if($execute){'Yellow'}else{'Green'})
Write-Host ("Plan      : {0}" -f $PlanPath) -ForegroundColor Green
Write-Host ("Manifest  : {0}" -f $ManifestPath) -ForegroundColor Green
Write-Host ("Package   : {0}" -f (Get-Prop $manifest 'package_id' 'UNKNOWN')) -ForegroundColor Green

if (-not $execute) {
    Write-Host 'HUMAN GATE: DRY RUN ONLY — NO SYSTEM PAYLOAD MUTATION' -ForegroundColor Green
} else {
    Write-Host 'HUMAN GATE: APPROVED EXECUTION' -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# RECEIPT
# ------------------------------------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$receiptPath = Join-Path $reportRoot "VERTEX_ENV2_RECEIPT.$stamp.json"
$summaryPath = Join-Path $reportRoot "VERTEX_ENV2_RECEIPT.$stamp.txt"

$receipt = [ordered]@{
    schema = $Schema
    mission_id = $MissionId
    execution_id = "ENV2-$stamp"
    mode = $Mode
    approved = $execute
    approval_token_verified = ($execute -and $Approval -eq $RequiredApproval)
    started_at = (Get-Date).ToString('o')
    plan_path = $PlanPath
    plan_sha256 = Get-Sha256 $PlanPath
    manifest_path = $ManifestPath
    manifest_sha256 = Get-Sha256 $ManifestPath
    package_id = Get-Prop $manifest 'package_id' 'UNKNOWN'
    target_role = Get-Prop $manifest 'target_role' 'UNSPECIFIED'
    operations = @()
    mutation_policy = [ordered]@{
        filesystem_create = $true
        filesystem_copy = $true
        overwrite = $false
        delete = $false
        registry = $false
        services = $false
        firewall = $false
        environment = $false
        drivers = $false
        arbitrary_commands = $false
    }
    completed_at = $null
    status = 'RUNNING'
}

$ops = @(Get-Prop $manifest 'operations' @())
$index = 0

foreach ($op in $ops) {
    $index++
    $type = [string](Get-Prop $op 'type' '')
    $source = [string](Get-Prop $op 'source' '')
    $destination = [string](Get-Prop $op 'destination' '')

    Write-Host ("[{0}/{1}] {2}" -f $index, $ops.Count, $type) -ForegroundColor Yellow

    $opReceipt = New-OperationReceipt -Index $index -Type $type -Source $source -Destination $destination

    try {
        switch ($type) {
            'ensure_directory' {
                Invoke-EnsureDirectory -Operation $op -Receipt $opReceipt -Execute $execute
            }
            'copy_file' {
                Invoke-CopyFile -Operation $op -Receipt $opReceipt -Execute $execute
            }
            'copy_tree' {
                Invoke-CopyTree -Operation $op -Receipt $opReceipt -Execute $execute
            }
            default {
                throw "Operation is not implemented: $type"
            }
        }

        Write-Host ("  {0}" -f $opReceipt.status) -ForegroundColor Green
    }
    catch {
        $opReceipt.status = 'RED'
        $opReceipt.error = $_.Exception.Message
        $receipt.operations += [pscustomobject]$opReceipt
        $receipt.status = 'RED'
        $receipt.completed_at = (Get-Date).ToString('o')

        $receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receiptPath -Encoding utf8

        throw
    }

    $receipt.operations += [pscustomobject]$opReceipt
}

$receipt.completed_at = (Get-Date).ToString('o')
$receipt.status = if ($execute) { 'EXECUTED_GREEN' } else { 'DRY_RUN_GREEN' }

$receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receiptPath -Encoding utf8

$summary = @"
============================================================
 VERTEX ENV-2 — EXECUTION RECEIPT
============================================================
 Execution ID     : $($receipt.execution_id)
 Mode             : $Mode
 Status           : $($receipt.status)
 Package          : $($receipt.package_id)
 Target Role      : $($receipt.target_role)

 Plan             : $PlanPath
 Manifest         : $ManifestPath

 Operations       : $($receipt.operations.Count)
 Receipt JSON     : $receiptPath
 Receipt TXT      : $summaryPath

 SAFETY BOUNDARY
  Overwrite       : DENIED
  Delete          : DENIED
  Registry        : DENIED
  Services        : DENIED
  Firewall        : DENIED
  PATH/Env        : DENIED
  Drivers         : DENIED
  Shell Commands  : DENIED

 NEXT
  If DryRun is correct:
    re-run with:
      -Mode Execute -Approval APPROVE-ENV2

  After Execute:
    run ENV-0 again for independent verification.
============================================================
"@

$summary | Set-Content -LiteralPath $summaryPath -Encoding utf8
Write-Host $summary -ForegroundColor Green
