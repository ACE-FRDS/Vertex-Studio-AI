#requires -Version 7.0
<#
VERTEX ENV-2 V2.7.3 — TRANSACTION DISPATCH / TYPED HANDOFF
ZERO SYSTEM MUTATION / ZERO PROVIDER INVOCATION

PURPOSE
  Convert the latest Provider Router decision into a typed transaction
  dispatch envelope for downstream provider execution.

FLOW
  ROUTER DECISION
    -> VALIDATE ADMISSION
    -> RESOLVE PROVIDER
    -> BUILD TYPED ENVELOPE
    -> ATTACH POLICY / EVIDENCE / ROLLBACK CONTRACT
    -> WRITE DISPATCH PACKAGE

IMPORTANT
  This stage does NOT invoke the provider.
  It only prepares the handoff contract.

ZERO SYSTEM MUTATION.
#>

[CmdletBinding()]
param(
    [string]$RouterDecisionPath = '',
    [string]$TransactionId = '',
    [string]$CandidateId = '',
    [string]$EvidencePath = '',
    [string]$SnapshotPath = '',
    [string]$ApprovalToken = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$CoreRoot   = Join-Path $ReportRoot '_transaction_core'
$DispatchRoot = Join-Path $CoreRoot '_dispatch'

if (-not (Test-Path -LiteralPath $DispatchRoot)) {
    New-Item -ItemType Directory -Path $DispatchRoot -Force | Out-Null
}

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

function New-DispatchId {
    return 'VDSP-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.7.3 — TRANSACTION DISPATCH / TYPED HANDOFF' -ForegroundColor Magenta
Write-Host ' ROUTER DECISION -> ENVELOPE -> PROVIDER HANDOFF' -ForegroundColor Magenta
Write-Host ' ZERO SYSTEM MUTATION / ZERO PROVIDER INVOCATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

# ------------------------------------------------------------
# Resolve router decision
# ------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($RouterDecisionPath)) {
    $latest = Get-ChildItem -LiteralPath $CoreRoot -Filter 'VERTEX_PROVIDER_ROUTER_DECISION.*.json' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw 'No V2.7.2 provider router decision report found.'
    }

    $RouterDecisionPath = $latest.FullName
}

if (-not (Test-Path -LiteralPath $RouterDecisionPath -PathType Leaf)) {
    throw "Router decision not found: $RouterDecisionPath"
}

$router = Get-Content -LiteralPath $RouterDecisionPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80

$decision = [string](Get-SafeProperty -Object $router.admission -Name 'decision' -Default 'DENY')
$providerName = [string](Get-SafeProperty -Object $router.route -Name 'provider_name' -Default '')
$resourceType = [string](Get-SafeProperty -Object $router.request -Name 'resource_type' -Default '')
$operation = [string](Get-SafeProperty -Object $router.request -Name 'operation' -Default '')
$maxRisk = [string](Get-SafeProperty -Object $router.request -Name 'max_risk' -Default '')
$requireRollback = [bool](Get-SafeProperty -Object $router.request -Name 'require_rollback' -Default $true)
$humanGateRequired = [bool](Get-SafeProperty -Object $router.admission -Name 'human_gate_required' -Default $true)
$blockedBy = @(Get-SafeProperty -Object $router.capability -Name 'blocked_by' -Default @())
$riskClass = [string](Get-SafeProperty -Object $router.capability -Name 'risk_class' -Default 'CRITICAL')
$rollbackReady = [bool](Get-SafeProperty -Object $router.capability -Name 'rollback_ready' -Default $false)

Write-Host ''
Write-Host '[1/4] ROUTER DECISION LOAD' -ForegroundColor Cyan
Write-Host "  Router Decision : $RouterDecisionPath"
Write-Host "  Decision        : $decision"
Write-Host "  Provider        : $providerName"
Write-Host "  Resource        : $resourceType"
Write-Host "  Operation       : $operation"

# ------------------------------------------------------------
# Admission interpretation
# ------------------------------------------------------------
Write-Host ''
Write-Host '[2/4] HANDOFF ADMISSION' -ForegroundColor Cyan

$dispatchState = 'DENIED'
$dispatchReason = ''

switch ($decision) {
    'ADMIT' {
        $dispatchState = 'READY_FOR_PROVIDER'
        $dispatchReason = 'Router admitted execution.'
    }

    'HOLD' {
        $dispatchState = 'HOLD_FOR_PRECONDITION'
        $dispatchReason = 'Router requires precondition resolution before provider invocation.'
    }

    default {
        $dispatchState = 'DENIED'
        $dispatchReason = 'Router denied provider execution.'
    }
}

Write-Host "  Dispatch State  : $dispatchState"
Write-Host "  Reason          : $dispatchReason"

# ------------------------------------------------------------
# Typed envelope
# ------------------------------------------------------------
Write-Host ''
Write-Host '[3/4] BUILD TYPED ENVELOPE' -ForegroundColor Cyan

$dispatchId = New-DispatchId

if ([string]::IsNullOrWhiteSpace($TransactionId)) {
    $TransactionId = 'VTXN-PENDING-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
}

$evidenceRef = $null
if ($EvidencePath) {
    if (-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf)) {
        throw "Evidence path not found: $EvidencePath"
    }

    $evidenceRef = [ordered]@{
        path = $EvidencePath
        exists = $true
    }
}

$snapshotRef = $null
if ($SnapshotPath) {
    if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) {
        throw "Snapshot path not found: $SnapshotPath"
    }

    $snapshotRef = [ordered]@{
        path = $SnapshotPath
        exists = $true
    }
}

$approval = [ordered]@{
    required = $humanGateRequired
    token_present = -not [string]::IsNullOrWhiteSpace($ApprovalToken)
    token_value = if ($ApprovalToken) { '[PRESENT_REDACTED]' } else { '' }
}

$preconditions = [System.Collections.Generic.List[string]]::new()

if ($decision -eq 'ADMIT') {
    $preconditions.Add('Router decision remains ADMIT at provider invocation time.')
}

if ($humanGateRequired) {
    $preconditions.Add('Human approval must be present before mutation.')
}

if ($requireRollback) {
    $preconditions.Add('Rollback contract must remain valid before mutation.')
}

if ($blockedBy.Count -gt 0) {
    foreach ($b in $blockedBy) {
        $preconditions.Add("Resolve blocker before provider invocation: $b")
    }
}

$rollbackContract = [ordered]@{
    required = $requireRollback
    provider_declared_ready = $rollbackReady
    snapshot_required = $requireRollback
    verify_after_rollback = $true
    rollback_only_mutated_resources = $true
    third_party_drift_policy = 'DENY_AUTOMATIC_ROLLBACK_IF_IDENTITY_DRIFTED'
}

$verificationContract = [ordered]@{
    verify_after_each_mutation = $true
    final_verify_required = $true
    commit_only_if_all_green = $true
    post_commit_verification = $true
}

$typedEnvelope = [ordered]@{
    schema = 'vertex.transaction.dispatch-envelope.v1'
    version = '2.7.3'
    dispatch_id = $dispatchId
    transaction_id = $TransactionId
    candidate_id = $CandidateId
    created_at = (Get-Date).ToString('o')

    source_router_decision = $RouterDecisionPath

    routing = [ordered]@{
        provider_name = $providerName
        resource_type = $resourceType
        operation = $operation
    }

    admission = [ordered]@{
        router_decision = $decision
        dispatch_state = $dispatchState
        risk_class = $riskClass
        max_risk = $maxRisk
        blocked_by = $blockedBy
    }

    payload = [ordered]@{
        evidence = $evidenceRef
        snapshot = $snapshotRef
    }

    approval = $approval
    rollback_contract = $rollbackContract
    verification_contract = $verificationContract

    preconditions = @($preconditions)

    typed_handoff = [ordered]@{
        sender = 'VertexTransactionCore'
        receiver = $providerName
        contract = 'vertex.transaction.provider-handoff.v1'
        immutable_after_dispatch = $true
        provider_must_revalidate_live_state = $true
        provider_must_emit_receipt = $true
        provider_must_return_terminal_state = $true
    }

    safety = [ordered]@{
        system_mutation = 'NONE'
        provider_invocation = 'NONE'
        dispatch_only = $true
    }
}

Write-Host "  Dispatch ID     : $dispatchId"
Write-Host "  Transaction ID  : $TransactionId"
Write-Host "  Receiver        : $providerName"
Write-Host "  Preconditions   : $($preconditions.Count)"
Write-Host "  Rollback Req.   : $requireRollback"
Write-Host "  Human Gate Req. : $humanGateRequired"

# ------------------------------------------------------------
# Write dispatch package
# ------------------------------------------------------------
Write-Host ''
Write-Host '[4/4] WRITE DISPATCH PACKAGE' -ForegroundColor Cyan

$dispatchDir = Join-Path $DispatchRoot $dispatchId
New-Item -ItemType Directory -Path $dispatchDir -Force | Out-Null

$envelopePath = Join-Path $dispatchDir 'dispatch_envelope.json'
$statusPath = Join-Path $dispatchDir 'DISPATCH_STATUS.txt'
$receiptPath = Join-Path $CoreRoot "VERTEX_TRANSACTION_DISPATCH.$dispatchId.json"

$typedEnvelope | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $envelopePath -Encoding UTF8
$typedEnvelope | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $receiptPath -Encoding UTF8

@(
    '============================================================',
    ' VERTEX TRANSACTION DISPATCH V2.7.3',
    '============================================================',
    " Dispatch ID       : $dispatchId",
    " Transaction ID    : $TransactionId",
    " Candidate ID      : $CandidateId",
    " Provider          : $providerName",
    " Resource Type     : $resourceType",
    " Operation         : $operation",
    " Router Decision   : $decision",
    " Dispatch State    : $dispatchState",
    " Risk              : $riskClass",
    " Rollback Required : $requireRollback",
    " Human Gate        : $humanGateRequired",
    '',
    " Blocked By        : $(if($blockedBy.Count){$blockedBy -join ', '}else{'NONE'})",
    '',
    ' PROVIDER INVOCATION : NONE',
    ' SYSTEM MUTATION     : NONE',
    '',
    " Envelope          : $envelopePath",
    " Receipt           : $receiptPath",
    '============================================================'
) | Set-Content -LiteralPath $statusPath -Encoding UTF8

Write-Host "  Package   : $dispatchDir"
Write-Host "  Envelope  : $envelopePath"
Write-Host "  Receipt   : $receiptPath"

Write-Host ''
$color = switch ($dispatchState) {
    'READY_FOR_PROVIDER'      { 'Green' }
    'HOLD_FOR_PRECONDITION'   { 'Yellow' }
    default                   { 'Red' }
}

Write-Host '============================================================' -ForegroundColor $color
Write-Host " V2.7.3 TRANSACTION DISPATCH : $dispatchState" -ForegroundColor $color
Write-Host ' PROVIDER INVOCATION : NONE'
Write-Host ' ZERO SYSTEM MUTATION'
Write-Host '============================================================' -ForegroundColor $color
