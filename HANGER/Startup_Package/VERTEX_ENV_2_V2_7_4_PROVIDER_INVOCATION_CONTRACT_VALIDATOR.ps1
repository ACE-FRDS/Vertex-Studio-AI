#requires -Version 7.0
<#
VERTEX ENV-2 V2.7.4 — PROVIDER INVOCATION CONTRACT VALIDATOR
ZERO SYSTEM MUTATION / ZERO PROVIDER EXECUTION

PURPOSE
  Validate a V2.7.3 typed dispatch envelope from the provider side.

VALIDATION
  - Envelope schema/version
  - Receiver/provider identity
  - Resource type
  - Operation
  - Router/dispatch admission state
  - Approval contract
  - Rollback contract
  - Snapshot/evidence requirements
  - Preconditions
  - Typed handoff contract
  - Provider revalidation/receipt obligations

RESULT
  ACCEPT
  HOLD
  REJECT

This stage DOES NOT invoke the provider.
#>

[CmdletBinding()]
param(
    [string]$DispatchEnvelopePath = '',

    [string]$ExpectedProvider = 'VertexFirewallProvider',

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

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.7.4 — PROVIDER CONTRACT VALIDATOR' -ForegroundColor Magenta
Write-Host ' ENVELOPE -> CONTRACT CHECK -> ACCEPT / HOLD / REJECT' -ForegroundColor Magenta
Write-Host ' ZERO SYSTEM MUTATION / ZERO PROVIDER EXECUTION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

if ([string]::IsNullOrWhiteSpace($DispatchEnvelopePath)) {
    $latest = Get-ChildItem -LiteralPath $DispatchRoot -Filter 'dispatch_envelope.json' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw 'No V2.7.3 dispatch envelope found.'
    }

    $DispatchEnvelopePath = $latest.FullName
}

if (-not (Test-Path -LiteralPath $DispatchEnvelopePath -PathType Leaf)) {
    throw "Dispatch envelope not found: $DispatchEnvelopePath"
}

$env = Get-Content -LiteralPath $DispatchEnvelopePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80

$schema         = [string](Get-SafeProperty -Object $env -Name 'schema' -Default '')
$version        = [string](Get-SafeProperty -Object $env -Name 'version' -Default '')
$dispatchId     = [string](Get-SafeProperty -Object $env -Name 'dispatch_id' -Default '')
$transactionId  = [string](Get-SafeProperty -Object $env -Name 'transaction_id' -Default '')
$candidateId    = [string](Get-SafeProperty -Object $env -Name 'candidate_id' -Default '')

$routing        = Get-SafeProperty -Object $env -Name 'routing' -Default $null
$admission      = Get-SafeProperty -Object $env -Name 'admission' -Default $null
$payload        = Get-SafeProperty -Object $env -Name 'payload' -Default $null
$approval       = Get-SafeProperty -Object $env -Name 'approval' -Default $null
$rollback       = Get-SafeProperty -Object $env -Name 'rollback_contract' -Default $null
$verification   = Get-SafeProperty -Object $env -Name 'verification_contract' -Default $null
$typedHandoff   = Get-SafeProperty -Object $env -Name 'typed_handoff' -Default $null
$preconditions  = @(Get-SafeProperty -Object $env -Name 'preconditions' -Default @())

$providerName   = [string](Get-SafeProperty -Object $routing -Name 'provider_name' -Default '')
$resourceType   = [string](Get-SafeProperty -Object $routing -Name 'resource_type' -Default '')
$operation      = [string](Get-SafeProperty -Object $routing -Name 'operation' -Default '')
$routerDecision = [string](Get-SafeProperty -Object $admission -Name 'router_decision' -Default '')
$dispatchState  = [string](Get-SafeProperty -Object $admission -Name 'dispatch_state' -Default '')
$blockedBy      = @(Get-SafeProperty -Object $admission -Name 'blocked_by' -Default @())

Write-Host ''
Write-Host '[1/4] ENVELOPE IDENTITY' -ForegroundColor Cyan
Write-Host "  Envelope       : $DispatchEnvelopePath"
Write-Host "  Schema         : $schema"
Write-Host "  Version        : $version"
Write-Host "  Dispatch ID    : $dispatchId"
Write-Host "  Transaction ID : $transactionId"
Write-Host "  Candidate ID   : $candidateId"
Write-Host "  Receiver       : $providerName"
Write-Host "  Expected       : $ExpectedProvider"

$failures = [System.Collections.Generic.List[string]]::new()
$holds    = [System.Collections.Generic.List[string]]::new()
$passes   = [System.Collections.Generic.List[string]]::new()

# ------------------------------------------------------------
# Schema / identity checks
# ------------------------------------------------------------
if ($schema -ne 'vertex.transaction.dispatch-envelope.v1') {
    $failures.Add("SCHEMA_MISMATCH:$schema")
}
else {
    $passes.Add('Schema valid.')
}

if ($version -ne '2.7.3') {
    $holds.Add("UNEXPECTED_ENVELOPE_VERSION:$version")
}
else {
    $passes.Add('Envelope version recognized.')
}

if ([string]::IsNullOrWhiteSpace($dispatchId)) {
    $failures.Add('DISPATCH_ID_MISSING')
}

if ([string]::IsNullOrWhiteSpace($transactionId)) {
    $failures.Add('TRANSACTION_ID_MISSING')
}

if ($providerName -ne $ExpectedProvider) {
    $failures.Add("RECEIVER_MISMATCH:$providerName->$ExpectedProvider")
}
else {
    $passes.Add('Receiver identity match.')
}

if ([string]::IsNullOrWhiteSpace($resourceType)) {
    $failures.Add('RESOURCE_TYPE_MISSING')
}

if ([string]::IsNullOrWhiteSpace($operation)) {
    $failures.Add('OPERATION_MISSING')
}

# ------------------------------------------------------------
# Admission / precondition checks
# ------------------------------------------------------------
Write-Host ''
Write-Host '[2/4] ADMISSION & PRECONDITIONS' -ForegroundColor Cyan
Write-Host "  Router Decision : $routerDecision"
Write-Host "  Dispatch State  : $dispatchState"
Write-Host "  Blocked By      : $(if($blockedBy.Count){$blockedBy -join ', '}else{'NONE'})"
Write-Host "  Preconditions   : $($preconditions.Count)"

if ($routerDecision -eq 'DENY' -or $dispatchState -eq 'DENIED') {
    $failures.Add('ROUTER_DENIED')
}

if ($routerDecision -eq 'HOLD' -or $dispatchState -eq 'HOLD_FOR_PRECONDITION') {
    $holds.Add('ROUTER_HOLD_REQUIRES_PRECONDITION_RESOLUTION')
}

foreach ($b in $blockedBy) {
    if ($b) {
        $holds.Add("UNRESOLVED_BLOCKER:$b")
    }
}

# ------------------------------------------------------------
# Approval / rollback / payload contracts
# ------------------------------------------------------------
Write-Host ''
Write-Host '[3/4] CONTRACT VALIDATION' -ForegroundColor Cyan

$approvalRequired = [bool](Get-SafeProperty -Object $approval -Name 'required' -Default $true)
$approvalPresentInEnvelope = [bool](Get-SafeProperty -Object $approval -Name 'token_present' -Default $false)
$approvalSuppliedNow = -not [string]::IsNullOrWhiteSpace($ApprovalToken)

Write-Host "  Approval Required     : $approvalRequired"
Write-Host "  Approval In Envelope  : $approvalPresentInEnvelope"
Write-Host "  Approval Supplied Now : $approvalSuppliedNow"

if ($approvalRequired -and -not ($approvalPresentInEnvelope -or $approvalSuppliedNow)) {
    $holds.Add('HUMAN_APPROVAL_REQUIRED')
}
elseif ($approvalRequired) {
    $passes.Add('Human approval requirement satisfied or supplied.')
}

$rollbackRequired = [bool](Get-SafeProperty -Object $rollback -Name 'required' -Default $true)
$rollbackReady = [bool](Get-SafeProperty -Object $rollback -Name 'provider_declared_ready' -Default $false)
$snapshotRequired = [bool](Get-SafeProperty -Object $rollback -Name 'snapshot_required' -Default $rollbackRequired)

Write-Host "  Rollback Required     : $rollbackRequired"
Write-Host "  Provider Rollback     : $rollbackReady"
Write-Host "  Snapshot Required     : $snapshotRequired"

if ($rollbackRequired -and -not $rollbackReady) {
    $failures.Add('ROLLBACK_REQUIRED_BUT_PROVIDER_NOT_READY')
}
elseif ($rollbackRequired) {
    $passes.Add('Rollback provider readiness satisfied.')
}

$evidence = Get-SafeProperty -Object $payload -Name 'evidence' -Default $null
$snapshot = Get-SafeProperty -Object $payload -Name 'snapshot' -Default $null

$evidencePath = [string](Get-SafeProperty -Object $evidence -Name 'path' -Default '')
$snapshotPath = [string](Get-SafeProperty -Object $snapshot -Name 'path' -Default '')

if ($evidencePath) {
    if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
        $failures.Add("EVIDENCE_PATH_MISSING:$evidencePath")
    }
    else {
        $passes.Add('Evidence path exists.')
    }
}

if ($snapshotRequired) {
    if ([string]::IsNullOrWhiteSpace($snapshotPath)) {
        $holds.Add('SNAPSHOT_REQUIRED_BUT_NOT_ATTACHED')
    }
    elseif (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
        $failures.Add("SNAPSHOT_PATH_MISSING:$snapshotPath")
    }
    else {
        $passes.Add('Snapshot path exists.')
    }
}

$verifyEach = [bool](Get-SafeProperty -Object $verification -Name 'verify_after_each_mutation' -Default $false)
$finalVerify = [bool](Get-SafeProperty -Object $verification -Name 'final_verify_required' -Default $false)
$commitAllGreen = [bool](Get-SafeProperty -Object $verification -Name 'commit_only_if_all_green' -Default $false)
$postCommit = [bool](Get-SafeProperty -Object $verification -Name 'post_commit_verification' -Default $false)

if (-not $verifyEach)     { $failures.Add('VERIFY_AFTER_EACH_MUTATION_REQUIRED') }
if (-not $finalVerify)    { $failures.Add('FINAL_VERIFY_REQUIRED') }
if (-not $commitAllGreen) { $failures.Add('COMMIT_ONLY_IF_ALL_GREEN_REQUIRED') }
if (-not $postCommit)     { $failures.Add('POST_COMMIT_VERIFICATION_REQUIRED') }

$sender = [string](Get-SafeProperty -Object $typedHandoff -Name 'sender' -Default '')
$receiver = [string](Get-SafeProperty -Object $typedHandoff -Name 'receiver' -Default '')
$contract = [string](Get-SafeProperty -Object $typedHandoff -Name 'contract' -Default '')
$mustRevalidate = [bool](Get-SafeProperty -Object $typedHandoff -Name 'provider_must_revalidate_live_state' -Default $false)
$mustReceipt = [bool](Get-SafeProperty -Object $typedHandoff -Name 'provider_must_emit_receipt' -Default $false)
$mustTerminal = [bool](Get-SafeProperty -Object $typedHandoff -Name 'provider_must_return_terminal_state' -Default $false)

if ($sender -ne 'VertexTransactionCore') {
    $failures.Add("INVALID_SENDER:$sender")
}

if ($receiver -ne $ExpectedProvider) {
    $failures.Add("HANDOFF_RECEIVER_MISMATCH:$receiver->$ExpectedProvider")
}

if ($contract -ne 'vertex.transaction.provider-handoff.v1') {
    $failures.Add("HANDOFF_CONTRACT_MISMATCH:$contract")
}

if (-not $mustRevalidate) { $failures.Add('PROVIDER_LIVE_REVALIDATION_REQUIRED') }
if (-not $mustReceipt)    { $failures.Add('PROVIDER_RECEIPT_REQUIRED') }
if (-not $mustTerminal)   { $failures.Add('PROVIDER_TERMINAL_STATE_REQUIRED') }

# ------------------------------------------------------------
# Decision
# ------------------------------------------------------------
Write-Host ''
Write-Host '[4/4] PROVIDER CONTRACT DECISION' -ForegroundColor Cyan

$decision = 'ACCEPT'

if ($failures.Count -gt 0) {
    $decision = 'REJECT'
}
elseif ($holds.Count -gt 0) {
    $decision = 'HOLD'
}

$color = switch ($decision) {
    'ACCEPT' { 'Green' }
    'HOLD'   { 'Yellow' }
    default  { 'Red' }
}

Write-Host "  DECISION : $decision" -ForegroundColor $color

if ($passes.Count -gt 0) {
    Write-Host "  Pass     : $($passes -join ' | ')"
}

if ($holds.Count -gt 0) {
    Write-Host "  Hold     : $($holds -join ' | ')"
}

if ($failures.Count -gt 0) {
    Write-Host "  Reject   : $($failures -join ' | ')"
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $CoreRoot "VERTEX_PROVIDER_CONTRACT_VALIDATION.$stamp.json"
$txt  = Join-Path $CoreRoot "VERTEX_PROVIDER_CONTRACT_VALIDATION.$stamp.txt"

$report = [ordered]@{
    schema = 'vertex.transaction.provider-contract-validation.v1'
    version = '2.7.4'
    generated_at = (Get-Date).ToString('o')
    dispatch_envelope = $DispatchEnvelopePath

    provider = [ordered]@{
        expected = $ExpectedProvider
        actual = $providerName
    }

    transaction = [ordered]@{
        dispatch_id = $dispatchId
        transaction_id = $transactionId
        candidate_id = $candidateId
        resource_type = $resourceType
        operation = $operation
    }

    validation = [ordered]@{
        decision = $decision
        passes = @($passes)
        holds = @($holds)
        failures = @($failures)
    }

    contracts = [ordered]@{
        approval_required = $approvalRequired
        rollback_required = $rollbackRequired
        rollback_ready = $rollbackReady
        snapshot_required = $snapshotRequired
        verify_after_each_mutation = $verifyEach
        final_verify_required = $finalVerify
        commit_only_if_all_green = $commitAllGreen
        post_commit_verification = $postCommit
        provider_live_revalidation = $mustRevalidate
        provider_receipt = $mustReceipt
        provider_terminal_state = $mustTerminal
    }

    safety = [ordered]@{
        system_mutation = 'NONE'
        provider_execution = 'NONE'
        validation_only = $true
    }
}

$report | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX PROVIDER CONTRACT VALIDATION V2.7.4',
    '============================================================',
    " Dispatch ID       : $dispatchId",
    " Transaction ID    : $transactionId",
    " Candidate ID      : $candidateId",
    " Expected Provider : $ExpectedProvider",
    " Actual Provider   : $providerName",
    " Resource Type     : $resourceType",
    " Operation         : $operation",
    " Decision          : $decision",
    '',
    " Holds             : $(if($holds.Count){$holds -join ', '}else{'NONE'})",
    " Rejects           : $(if($failures.Count){$failures -join ', '}else{'NONE'})",
    '',
    ' SYSTEM MUTATION   : NONE',
    ' PROVIDER EXECUTION: NONE',
    '',
    " JSON              : $json",
    " TXT               : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host "  JSON     : $json"
Write-Host "  TXT      : $txt"

Write-Host ''
Write-Host '============================================================' -ForegroundColor $color
Write-Host " V2.7.4 PROVIDER CONTRACT VALIDATION : $decision" -ForegroundColor $color
Write-Host ' ZERO SYSTEM MUTATION'
Write-Host ' ZERO PROVIDER EXECUTION'
Write-Host '============================================================' -ForegroundColor $color
