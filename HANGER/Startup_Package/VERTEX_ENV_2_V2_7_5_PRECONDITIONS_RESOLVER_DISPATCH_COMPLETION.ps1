#requires -Version 7.0
<#
VERTEX ENV-2 V2.7.5 — PRECONDITIONS RESOLVER / DISPATCH COMPLETION
ZERO SYSTEM MUTATION / ZERO PROVIDER EXECUTION

PURPOSE
  Resolve HOLD conditions from V2.7.4 provider contract validation.

RESOLUTION TARGETS
  - Administrator session
  - Human approval
  - Snapshot attachment
  - Router re-evaluation

FLOW
  LOAD LATEST VALIDATION
    -> LOAD ORIGINAL DISPATCH
    -> RECHECK CURRENT SESSION
    -> ATTACH SNAPSHOT
    -> APPLY APPROVAL
    -> RE-EVALUATE ADMISSION
    -> WRITE COMPLETED DISPATCH ENVELOPE

RESULT
  READY_FOR_PROVIDER
  HOLD_FOR_PRECONDITION
  DENIED

No provider execution occurs here.
#>

[CmdletBinding()]
param(
    [string]$DispatchEnvelopePath = '',
    [string]$SnapshotPath = '',
    [string]$EvidencePath = '',
    [string]$ApprovalToken = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot   = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$CoreRoot     = Join-Path $ReportRoot '_transaction_core'
$DispatchRoot = Join-Path $CoreRoot '_dispatch'

function Get-SafeProperty {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $Default }
    if ($null -eq $p.Value) { return $Default }
    return $p.Value
}

function Test-VertexAdministrator {
    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-LatestPreparedSnapshot {
    param([string]$ResourceType)

    # For firewall, use latest V2.5 prepared transaction snapshot.
    if ($ResourceType -eq 'WINDOWS_FIREWALL_RULE') {
        $txnRoot = Join-Path $ReportRoot '_transactions'
        $snapshot = Get-ChildItem -LiteralPath $txnRoot -Filter 'rollback_snapshot.json' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($snapshot) {
            return $snapshot.FullName
        }
    }

    return ''
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.7.5 — PRECONDITIONS RESOLVER' -ForegroundColor Magenta
Write-Host ' HOLD -> RESOLVE -> READY_FOR_PROVIDER' -ForegroundColor Magenta
Write-Host ' ZERO SYSTEM MUTATION / ZERO PROVIDER EXECUTION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

# ------------------------------------------------------------
# Resolve dispatch envelope
# ------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($DispatchEnvelopePath)) {
    $latest = Get-ChildItem -LiteralPath $DispatchRoot -Filter 'dispatch_envelope.json' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw 'No dispatch envelope found.'
    }

    $DispatchEnvelopePath = $latest.FullName
}

if (-not (Test-Path -LiteralPath $DispatchEnvelopePath -PathType Leaf)) {
    throw "Dispatch envelope not found: $DispatchEnvelopePath"
}

$env = Get-Content -LiteralPath $DispatchEnvelopePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80

$routing = Get-SafeProperty -Object $env -Name 'routing' -Default $null
$admission = Get-SafeProperty -Object $env -Name 'admission' -Default $null
$approval = Get-SafeProperty -Object $env -Name 'approval' -Default $null
$rollback = Get-SafeProperty -Object $env -Name 'rollback_contract' -Default $null
$payload = Get-SafeProperty -Object $env -Name 'payload' -Default $null

$dispatchId = [string](Get-SafeProperty -Object $env -Name 'dispatch_id' -Default '')
$transactionId = [string](Get-SafeProperty -Object $env -Name 'transaction_id' -Default '')
$candidateId = [string](Get-SafeProperty -Object $env -Name 'candidate_id' -Default '')

$providerName = [string](Get-SafeProperty -Object $routing -Name 'provider_name' -Default '')
$resourceType = [string](Get-SafeProperty -Object $routing -Name 'resource_type' -Default '')
$operation = [string](Get-SafeProperty -Object $routing -Name 'operation' -Default '')
$riskClass = [string](Get-SafeProperty -Object $admission -Name 'risk_class' -Default 'CRITICAL')
$maxRisk = [string](Get-SafeProperty -Object $admission -Name 'max_risk' -Default 'HIGH')
$routerDecision = [string](Get-SafeProperty -Object $admission -Name 'router_decision' -Default 'HOLD')

Write-Host ''
Write-Host '[1/4] LOAD HOLD ENVELOPE' -ForegroundColor Cyan
Write-Host "  Dispatch ID    : $dispatchId"
Write-Host "  Transaction ID : $transactionId"
Write-Host "  Candidate ID   : $candidateId"
Write-Host "  Provider       : $providerName"
Write-Host "  Resource       : $resourceType"
Write-Host "  Operation      : $operation"
Write-Host "  Router         : $routerDecision"

# ------------------------------------------------------------
# Resolve preconditions
# ------------------------------------------------------------
Write-Host ''
Write-Host '[2/4] RESOLVE PRECONDITIONS' -ForegroundColor Cyan

$isAdmin = Test-VertexAdministrator

$approvalRequired = [bool](Get-SafeProperty -Object $approval -Name 'required' -Default $true)
$approvalSatisfied = $true

if ($approvalRequired) {
    $approvalSatisfied = -not [string]::IsNullOrWhiteSpace($ApprovalToken)
}

$rollbackRequired = [bool](Get-SafeProperty -Object $rollback -Name 'required' -Default $true)
$rollbackReady = [bool](Get-SafeProperty -Object $rollback -Name 'provider_declared_ready' -Default $false)
$snapshotRequired = [bool](Get-SafeProperty -Object $rollback -Name 'snapshot_required' -Default $rollbackRequired)

if ([string]::IsNullOrWhiteSpace($SnapshotPath) -and $snapshotRequired) {
    $SnapshotPath = Get-LatestPreparedSnapshot -ResourceType $resourceType
}

$snapshotSatisfied = $true
if ($snapshotRequired) {
    $snapshotSatisfied = (-not [string]::IsNullOrWhiteSpace($SnapshotPath)) -and
                         (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)
}

$evidenceSatisfied = $true
if ($EvidencePath) {
    $evidenceSatisfied = Test-Path -LiteralPath $EvidencePath -PathType Leaf
}

$adminRequired = ($operation -eq 'EXECUTE' -and $resourceType -in @(
    'WINDOWS_FIREWALL_RULE',
    'WINDOWS_REGISTRY',
    'WINDOWS_SERVICE',
    'WINDOWS_ENVIRONMENT',
    'WINDOWS_SCHEDULED_TASK',
    'WINDOWS_CERTIFICATE'
))

$adminSatisfied = (-not $adminRequired) -or $isAdmin

Write-Host "  Administrator      : $isAdmin"
Write-Host "  Admin Required     : $adminRequired"
Write-Host "  Admin Satisfied    : $adminSatisfied"
Write-Host "  Approval Required  : $approvalRequired"
Write-Host "  Approval Satisfied : $approvalSatisfied"
Write-Host "  Rollback Required  : $rollbackRequired"
Write-Host "  Rollback Ready     : $rollbackReady"
Write-Host "  Snapshot Required  : $snapshotRequired"
Write-Host "  Snapshot Satisfied : $snapshotSatisfied"
Write-Host "  Evidence Satisfied : $evidenceSatisfied"

# ------------------------------------------------------------
# Re-evaluate admission
# ------------------------------------------------------------
Write-Host ''
Write-Host '[3/4] RE-EVALUATE ADMISSION' -ForegroundColor Cyan

$holds = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

if (-not $adminSatisfied) {
    $holds.Add('ADMIN_PRIVILEGE_REQUIRED')
}
else {
    $passes.Add('Administrator precondition satisfied.')
}

if (-not $approvalSatisfied) {
    $holds.Add('HUMAN_APPROVAL_REQUIRED')
}
elseif ($approvalRequired) {
    $passes.Add('Human approval satisfied.')
}

if ($rollbackRequired -and -not $rollbackReady) {
    $failures.Add('ROLLBACK_PROVIDER_NOT_READY')
}
elseif ($rollbackRequired) {
    $passes.Add('Rollback provider readiness satisfied.')
}

if (-not $snapshotSatisfied) {
    $holds.Add('SNAPSHOT_REQUIRED_BUT_NOT_AVAILABLE')
}
elseif ($snapshotRequired) {
    $passes.Add('Snapshot attached.')
}

if (-not $evidenceSatisfied) {
    $failures.Add('EVIDENCE_PATH_INVALID')
}

$decision = 'READY_FOR_PROVIDER'

if ($failures.Count -gt 0) {
    $decision = 'DENIED'
}
elseif ($holds.Count -gt 0) {
    $decision = 'HOLD_FOR_PRECONDITION'
}

Write-Host "  DECISION : $decision"

if ($passes.Count -gt 0) {
    Write-Host "  Pass     : $($passes -join ' | ')"
}

if ($holds.Count -gt 0) {
    Write-Host "  Hold     : $($holds -join ' | ')"
}

if ($failures.Count -gt 0) {
    Write-Host "  Reject   : $($failures -join ' | ')"
}

# ------------------------------------------------------------
# Build completed envelope
# ------------------------------------------------------------
Write-Host ''
Write-Host '[4/4] WRITE COMPLETED DISPATCH' -ForegroundColor Cyan

$completedId = 'VDSPC-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$completedDir = Join-Path $DispatchRoot $completedId
New-Item -ItemType Directory -Path $completedDir -Force | Out-Null

$completedEnvelope = [ordered]@{
    schema = 'vertex.transaction.completed-dispatch-envelope.v1'
    version = '2.7.5'
    dispatch_completion_id = $completedId
    source_dispatch_id = $dispatchId
    source_dispatch_envelope = $DispatchEnvelopePath
    transaction_id = $transactionId
    candidate_id = $candidateId
    completed_at = (Get-Date).ToString('o')

    routing = [ordered]@{
        provider_name = $providerName
        resource_type = $resourceType
        operation = $operation
    }

    admission = [ordered]@{
        prior_router_decision = $routerDecision
        completed_dispatch_state = $decision
        risk_class = $riskClass
        max_risk = $maxRisk
    }

    preconditions = [ordered]@{
        administrator = [ordered]@{
            required = $adminRequired
            satisfied = $adminSatisfied
        }
        approval = [ordered]@{
            required = $approvalRequired
            satisfied = $approvalSatisfied
            token = if ($approvalSatisfied -and $approvalRequired) { '[PRESENT_REDACTED]' } else { '' }
        }
        rollback = [ordered]@{
            required = $rollbackRequired
            provider_ready = $rollbackReady
        }
        snapshot = [ordered]@{
            required = $snapshotRequired
            satisfied = $snapshotSatisfied
            path = $SnapshotPath
        }
        evidence = [ordered]@{
            satisfied = $evidenceSatisfied
            path = $EvidencePath
        }
    }

    validation = [ordered]@{
        passes = @($passes)
        holds = @($holds)
        failures = @($failures)
    }

    typed_handoff = [ordered]@{
        sender = 'VertexTransactionCore'
        receiver = $providerName
        contract = 'vertex.transaction.provider-handoff.v1'
        provider_must_revalidate_live_state = $true
        provider_must_emit_receipt = $true
        provider_must_return_terminal_state = $true
        immutable_after_completion = $true
    }

    safety = [ordered]@{
        system_mutation = 'NONE'
        provider_execution = 'NONE'
        completion_only = $true
    }
}

$envelopePath = Join-Path $completedDir 'completed_dispatch_envelope.json'
$statusPath = Join-Path $completedDir 'COMPLETION_STATUS.txt'
$receiptPath = Join-Path $CoreRoot "VERTEX_DISPATCH_COMPLETION.$completedId.json"

$completedEnvelope | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $envelopePath -Encoding UTF8
$completedEnvelope | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $receiptPath -Encoding UTF8

@(
    '============================================================',
    ' VERTEX DISPATCH COMPLETION V2.7.5',
    '============================================================',
    " Completion ID      : $completedId",
    " Source Dispatch    : $dispatchId",
    " Transaction ID     : $transactionId",
    " Candidate ID       : $candidateId",
    " Provider           : $providerName",
    " Resource Type      : $resourceType",
    " Operation          : $operation",
    " Result             : $decision",
    '',
    " Admin Satisfied    : $adminSatisfied",
    " Approval Satisfied : $approvalSatisfied",
    " Snapshot Satisfied : $snapshotSatisfied",
    " Rollback Ready     : $rollbackReady",
    '',
    ' PROVIDER EXECUTION : NONE',
    ' SYSTEM MUTATION    : NONE',
    '',
    " Envelope           : $envelopePath",
    " Receipt            : $receiptPath",
    '============================================================'
) | Set-Content -LiteralPath $statusPath -Encoding UTF8

Write-Host "  Completion ID : $completedId"
Write-Host "  Package       : $completedDir"
Write-Host "  Envelope      : $envelopePath"
Write-Host "  Receipt       : $receiptPath"

$color = switch ($decision) {
    'READY_FOR_PROVIDER'       { 'Green' }
    'HOLD_FOR_PRECONDITION'    { 'Yellow' }
    default                    { 'Red' }
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor $color
Write-Host " V2.7.5 DISPATCH COMPLETION : $decision" -ForegroundColor $color
Write-Host ' ZERO SYSTEM MUTATION'
Write-Host ' ZERO PROVIDER EXECUTION'
Write-Host '============================================================' -ForegroundColor $color
