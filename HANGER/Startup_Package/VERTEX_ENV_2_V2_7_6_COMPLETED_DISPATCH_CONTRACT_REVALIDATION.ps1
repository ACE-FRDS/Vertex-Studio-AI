#requires -Version 7.0
<#
VERTEX ENV-2 V2.7.6 — COMPLETED DISPATCH CONTRACT REVALIDATION
READ ONLY / ZERO SYSTEM MUTATION / ZERO PROVIDER EXECUTION

PURPOSE
  Provider-side revalidation of the latest V2.7.5 completed dispatch envelope.
  ACCEPT is emitted only when the completed handoff is structurally valid and
  all recorded preconditions remain satisfied.

IMPORTANT
  This script does NOT execute the provider and does NOT mutate system state.
#>

[CmdletBinding()]
param(
    [string]$CompletedEnvelopePath = '',
    [string]$ExpectedProvider = 'VertexFirewallProvider'
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
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Test-VertexAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.7.6 — COMPLETED DISPATCH REVALIDATION' -ForegroundColor Magenta
Write-Host ' COMPLETED ENVELOPE -> LIVE PRECONDITIONS -> ACCEPT/HOLD/REJECT' -ForegroundColor Magenta
Write-Host ' READ ONLY / ZERO SYSTEM MUTATION / ZERO PROVIDER EXECUTION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

if ([string]::IsNullOrWhiteSpace($CompletedEnvelopePath)) {
    $latest = Get-ChildItem -LiteralPath $DispatchRoot -Filter 'completed_dispatch_envelope.json' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { throw 'No V2.7.5 completed dispatch envelope found.' }
    $CompletedEnvelopePath = $latest.FullName
}

if (-not (Test-Path -LiteralPath $CompletedEnvelopePath -PathType Leaf)) {
    throw "Completed dispatch envelope not found: $CompletedEnvelopePath"
}

$env = Get-Content -LiteralPath $CompletedEnvelopePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80

$schema = [string](Get-SafeProperty $env 'schema' '')
$version = [string](Get-SafeProperty $env 'version' '')
$completionId = [string](Get-SafeProperty $env 'dispatch_completion_id' '')
$transactionId = [string](Get-SafeProperty $env 'transaction_id' '')
$candidateId = [string](Get-SafeProperty $env 'candidate_id' '')

$routing = Get-SafeProperty $env 'routing' $null
$admission = Get-SafeProperty $env 'admission' $null
$pre = Get-SafeProperty $env 'preconditions' $null
$handoff = Get-SafeProperty $env 'typed_handoff' $null

$provider = [string](Get-SafeProperty $routing 'provider_name' '')
$resource = [string](Get-SafeProperty $routing 'resource_type' '')
$operation = [string](Get-SafeProperty $routing 'operation' '')
$state = [string](Get-SafeProperty $admission 'completed_dispatch_state' '')

$admin = Get-SafeProperty $pre 'administrator' $null
$approval = Get-SafeProperty $pre 'approval' $null
$rollback = Get-SafeProperty $pre 'rollback' $null
$snapshot = Get-SafeProperty $pre 'snapshot' $null
$evidence = Get-SafeProperty $pre 'evidence' $null

$failures = [System.Collections.Generic.List[string]]::new()
$holds = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

Write-Host ''
Write-Host '[1/4] COMPLETED ENVELOPE IDENTITY' -ForegroundColor Cyan
Write-Host "  Envelope       : $CompletedEnvelopePath"
Write-Host "  Completion ID  : $completionId"
Write-Host "  Transaction ID : $transactionId"
Write-Host "  Candidate ID   : $candidateId"
Write-Host "  Provider       : $provider"
Write-Host "  Resource       : $resource"
Write-Host "  Operation      : $operation"
Write-Host "  State          : $state"

if ($schema -ne 'vertex.transaction.completed-dispatch-envelope.v1') {
    $failures.Add("SCHEMA_MISMATCH:$schema")
} else { $passes.Add('Schema valid.') }

if ($version -ne '2.7.5') {
    $holds.Add("UNEXPECTED_VERSION:$version")
} else { $passes.Add('Version recognized.') }

if ($provider -ne $ExpectedProvider) {
    $failures.Add("RECEIVER_MISMATCH:$provider->$ExpectedProvider")
} else { $passes.Add('Receiver identity match.') }

if ($state -ne 'READY_FOR_PROVIDER') {
    $holds.Add("DISPATCH_NOT_READY:$state")
} else { $passes.Add('Completed dispatch is READY_FOR_PROVIDER.') }

Write-Host ''
Write-Host '[2/4] LIVE PRECONDITION REVALIDATION' -ForegroundColor Cyan

$isAdmin = Test-VertexAdministrator
$adminRequired = [bool](Get-SafeProperty $admin 'required' $false)
$approvalRequired = [bool](Get-SafeProperty $approval 'required' $false)
$approvalSatisfied = [bool](Get-SafeProperty $approval 'satisfied' $false)
$rollbackRequired = [bool](Get-SafeProperty $rollback 'required' $false)
$rollbackReady = [bool](Get-SafeProperty $rollback 'provider_ready' $false)
$snapshotRequired = [bool](Get-SafeProperty $snapshot 'required' $false)
$snapshotSatisfied = [bool](Get-SafeProperty $snapshot 'satisfied' $false)
$snapshotPath = [string](Get-SafeProperty $snapshot 'path' '')
$evidenceSatisfied = [bool](Get-SafeProperty $evidence 'satisfied' $true)
$evidencePath = [string](Get-SafeProperty $evidence 'path' '')

Write-Host "  Administrator Now : $isAdmin"
Write-Host "  Admin Required     : $adminRequired"
Write-Host "  Approval Satisfied : $approvalSatisfied"
Write-Host "  Rollback Ready     : $rollbackReady"
Write-Host "  Snapshot Satisfied : $snapshotSatisfied"

if ($adminRequired -and -not $isAdmin) {
    $holds.Add('ADMIN_PRIVILEGE_NO_LONGER_SATISFIED')
} elseif ($adminRequired) {
    $passes.Add('Administrator condition remains satisfied.')
}

if ($approvalRequired -and -not $approvalSatisfied) {
    $holds.Add('HUMAN_APPROVAL_NOT_SATISFIED')
} elseif ($approvalRequired) {
    $passes.Add('Human approval recorded.')
}

if ($rollbackRequired -and -not $rollbackReady) {
    $failures.Add('ROLLBACK_CONTRACT_NOT_READY')
} elseif ($rollbackRequired) {
    $passes.Add('Rollback contract ready.')
}

if ($snapshotRequired) {
    if (-not $snapshotSatisfied -or [string]::IsNullOrWhiteSpace($snapshotPath)) {
        $holds.Add('SNAPSHOT_NOT_ATTACHED')
    } elseif (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
        $failures.Add("SNAPSHOT_DISAPPEARED:$snapshotPath")
    } else {
        $passes.Add('Snapshot remains accessible.')
    }
}

if (-not $evidenceSatisfied) {
    $failures.Add('EVIDENCE_CONTRACT_NOT_SATISFIED')
} elseif ($evidencePath) {
    if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
        $failures.Add("EVIDENCE_DISAPPEARED:$evidencePath")
    } else {
        $passes.Add('Evidence remains accessible.')
    }
}

Write-Host ''
Write-Host '[3/4] TYPED HANDOFF CONTRACT' -ForegroundColor Cyan

$sender = [string](Get-SafeProperty $handoff 'sender' '')
$receiver = [string](Get-SafeProperty $handoff 'receiver' '')
$contract = [string](Get-SafeProperty $handoff 'contract' '')
$mustRevalidate = [bool](Get-SafeProperty $handoff 'provider_must_revalidate_live_state' $false)
$mustReceipt = [bool](Get-SafeProperty $handoff 'provider_must_emit_receipt' $false)
$mustTerminal = [bool](Get-SafeProperty $handoff 'provider_must_return_terminal_state' $false)
$immutable = [bool](Get-SafeProperty $handoff 'immutable_after_completion' $false)

if ($sender -ne 'VertexTransactionCore') { $failures.Add("INVALID_SENDER:$sender") }
if ($receiver -ne $ExpectedProvider) { $failures.Add("HANDOFF_RECEIVER_MISMATCH:$receiver") }
if ($contract -ne 'vertex.transaction.provider-handoff.v1') { $failures.Add("CONTRACT_MISMATCH:$contract") }
if (-not $mustRevalidate) { $failures.Add('LIVE_REVALIDATION_CONTRACT_MISSING') }
if (-not $mustReceipt) { $failures.Add('RECEIPT_CONTRACT_MISSING') }
if (-not $mustTerminal) { $failures.Add('TERMINAL_STATE_CONTRACT_MISSING') }
if (-not $immutable) { $failures.Add('IMMUTABILITY_CONTRACT_MISSING') }

if ($failures.Count -eq 0) {
    $passes.Add('Typed handoff contract valid.')
}

Write-Host "  Sender          : $sender"
Write-Host "  Receiver        : $receiver"
Write-Host "  Contract        : $contract"
Write-Host "  Live Revalidate : $mustRevalidate"
Write-Host "  Emit Receipt    : $mustReceipt"
Write-Host "  Terminal State  : $mustTerminal"
Write-Host "  Immutable       : $immutable"

Write-Host ''
Write-Host '[4/4] PROVIDER ACCEPTANCE DECISION' -ForegroundColor Cyan

$decision = 'ACCEPT'
if ($failures.Count -gt 0) {
    $decision = 'REJECT'
} elseif ($holds.Count -gt 0) {
    $decision = 'HOLD'
}

$color = switch ($decision) {
    'ACCEPT' { 'Green' }
    'HOLD'   { 'Yellow' }
    default  { 'Red' }
}

Write-Host "  DECISION : $decision" -ForegroundColor $color
if ($passes.Count -gt 0) { Write-Host "  Pass     : $($passes -join ' | ')" }
if ($holds.Count -gt 0) { Write-Host "  Hold     : $($holds -join ' | ')" }
if ($failures.Count -gt 0) { Write-Host "  Reject   : $($failures -join ' | ')" }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $CoreRoot "VERTEX_COMPLETED_DISPATCH_REVALIDATION.$stamp.json"
$txt = Join-Path $CoreRoot "VERTEX_COMPLETED_DISPATCH_REVALIDATION.$stamp.txt"

$report = [ordered]@{
    schema = 'vertex.transaction.completed-dispatch-revalidation.v1'
    version = '2.7.6'
    generated_at = (Get-Date).ToString('o')
    completed_envelope = $CompletedEnvelopePath
    completion_id = $completionId
    transaction_id = $transactionId
    candidate_id = $candidateId
    provider = $provider
    resource_type = $resource
    operation = $operation
    decision = $decision
    passes = @($passes)
    holds = @($holds)
    failures = @($failures)
    live = [ordered]@{
        administrator = $isAdmin
        snapshot_accessible = if ($snapshotPath) { Test-Path -LiteralPath $snapshotPath -PathType Leaf } else { $false }
        evidence_accessible = if ($evidencePath) { Test-Path -LiteralPath $evidencePath -PathType Leaf } else { $null }
    }
    safety = [ordered]@{
        system_mutation = 'NONE'
        provider_execution = 'NONE'
        revalidation_only = $true
    }
}

$report | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX COMPLETED DISPATCH REVALIDATION V2.7.6',
    '============================================================',
    " Completion ID  : $completionId",
    " Transaction ID : $transactionId",
    " Provider       : $provider",
    " Resource       : $resource",
    " Operation      : $operation",
    " Decision       : $decision",
    '',
    " Holds          : $(if($holds.Count){$holds -join ', '}else{'NONE'})",
    " Rejects        : $(if($failures.Count){$failures -join ', '}else{'NONE'})",
    '',
    ' SYSTEM MUTATION    : NONE',
    ' PROVIDER EXECUTION : NONE',
    '',
    " JSON           : $json",
    " TXT            : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host "  JSON     : $json"
Write-Host "  TXT      : $txt"

Write-Host ''
Write-Host '============================================================' -ForegroundColor $color
Write-Host " V2.7.6 COMPLETED DISPATCH REVALIDATION : $decision" -ForegroundColor $color
Write-Host ' ZERO SYSTEM MUTATION'
Write-Host ' ZERO PROVIDER EXECUTION'
Write-Host '============================================================' -ForegroundColor $color
