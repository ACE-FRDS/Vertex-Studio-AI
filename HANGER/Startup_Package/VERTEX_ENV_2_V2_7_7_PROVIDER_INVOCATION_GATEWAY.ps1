#requires -Version 7.0
<#
VERTEX ENV-2 V2.7.7 — PROVIDER INVOCATION GATEWAY
ACCEPTED HANDOFF ONLY / FIREWALL PROVIDER FIRST / EXPLICIT EXECUTION GATE

PURPOSE
  Bridge an ACCEPTed V2.7.6 completed dispatch into an actual provider executor.

SUPPORTED PROVIDERS
  - VertexFirewallProvider -> V2.6.1 Transaction Firewall Executor

SAFETY
  - Requires latest V2.7.6 decision == ACCEPT
  - Requires Administrator
  - Requires explicit Gateway Approval
  - Requires provider/resource/operation consistency
  - Requires completed dispatch == READY_FOR_PROVIDER
  - Revalidates snapshot availability
  - Revalidates accepted provider identity
  - Unsupported providers are DENIED
  - Gateway invokes only one mapped provider

IMPORTANT
  This script CAN invoke a mutating provider executor.
#>

[CmdletBinding()]
param(
    [ValidateSet('DryRun','Execute')]
    [string]$Mode = 'DryRun',

    [string]$CompletedEnvelopePath = '',
    [string]$RevalidationPath = '',

    [string]$CandidateId = '',

    [string]$Approval = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StartupRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$ReportRoot  = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$CoreRoot    = Join-Path $ReportRoot '_transaction_core'
$DispatchRoot = Join-Path $CoreRoot '_dispatch'

$FirewallExecutor = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_6_1_TRANSACTION_FIREWALL_EXECUTOR_PRIVILEGE_GATE.ps1'

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
    }
    catch {
        return $false
    }
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.7.7 — PROVIDER INVOCATION GATEWAY' -ForegroundColor Magenta
Write-Host ' ACCEPT -> FINAL VERIFY -> PROVIDER INVOCATION' -ForegroundColor Magenta
Write-Host ' FIREWALL PROVIDER FIRST' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

# ------------------------------------------------------------
# Resolve completed envelope
# ------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($CompletedEnvelopePath)) {
    $latest = Get-ChildItem -LiteralPath $DispatchRoot -Filter 'completed_dispatch_envelope.json' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw 'No completed dispatch envelope found.'
    }

    $CompletedEnvelopePath = $latest.FullName
}

if (-not (Test-Path -LiteralPath $CompletedEnvelopePath -PathType Leaf)) {
    throw "Completed envelope not found: $CompletedEnvelopePath"
}

# ------------------------------------------------------------
# Resolve revalidation receipt
# ------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($RevalidationPath)) {
    $latestReval = Get-ChildItem -LiteralPath $CoreRoot -Filter 'VERTEX_COMPLETED_DISPATCH_REVALIDATION.*.json' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latestReval) {
        throw 'No V2.7.6 completed dispatch revalidation receipt found.'
    }

    $RevalidationPath = $latestReval.FullName
}

if (-not (Test-Path -LiteralPath $RevalidationPath -PathType Leaf)) {
    throw "Revalidation receipt not found: $RevalidationPath"
}

$env = Get-Content -LiteralPath $CompletedEnvelopePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80
$reval = Get-Content -LiteralPath $RevalidationPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80

$routing = Get-SafeProperty $env 'routing' $null
$admission = Get-SafeProperty $env 'admission' $null
$pre = Get-SafeProperty $env 'preconditions' $null

$completionId = [string](Get-SafeProperty $env 'dispatch_completion_id' '')
$transactionId = [string](Get-SafeProperty $env 'transaction_id' '')
$envCandidateId = [string](Get-SafeProperty $env 'candidate_id' '')
$provider = [string](Get-SafeProperty $routing 'provider_name' '')
$resource = [string](Get-SafeProperty $routing 'resource_type' '')
$operation = [string](Get-SafeProperty $routing 'operation' '')
$dispatchState = [string](Get-SafeProperty $admission 'completed_dispatch_state' '')

$revalDecision = [string](Get-SafeProperty $reval 'decision' '')
$revalProvider = [string](Get-SafeProperty $reval 'provider' '')
$revalTxn = [string](Get-SafeProperty $reval 'transaction_id' '')
$revalCompletion = [string](Get-SafeProperty $reval 'completion_id' '')

if ([string]::IsNullOrWhiteSpace($CandidateId)) {
    $CandidateId = $envCandidateId
}

Write-Host ''
Write-Host '[1/5] ACCEPTANCE RECEIPT CHECK' -ForegroundColor Cyan
Write-Host "  Completed Envelope : $CompletedEnvelopePath"
Write-Host "  Revalidation       : $RevalidationPath"
Write-Host "  Completion ID      : $completionId"
Write-Host "  Transaction ID     : $transactionId"
Write-Host "  Candidate ID       : $CandidateId"
Write-Host "  Provider           : $provider"
Write-Host "  Resource           : $resource"
Write-Host "  Operation          : $operation"
Write-Host "  Dispatch State     : $dispatchState"
Write-Host "  Revalidation       : $revalDecision"

$guards = [System.Collections.Generic.List[string]]::new()

if ($revalDecision -ne 'ACCEPT') {
    $guards.Add("REVALIDATION_NOT_ACCEPTED:$revalDecision")
}

if ($revalProvider -ne $provider) {
    $guards.Add("PROVIDER_MISMATCH:$revalProvider->$provider")
}

if ($revalTxn -ne $transactionId) {
    $guards.Add("TRANSACTION_MISMATCH:$revalTxn->$transactionId")
}

if ($revalCompletion -ne $completionId) {
    $guards.Add("COMPLETION_MISMATCH:$revalCompletion->$completionId")
}

if ($dispatchState -ne 'READY_FOR_PROVIDER') {
    $guards.Add("DISPATCH_NOT_READY:$dispatchState")
}

if ($operation -ne 'EXECUTE') {
    $guards.Add("UNSUPPORTED_OPERATION:$operation")
}

# ------------------------------------------------------------
# Provider mapping
# ------------------------------------------------------------
Write-Host ''
Write-Host '[2/5] PROVIDER MAPPING' -ForegroundColor Cyan

$executorPath = ''
$mapped = $false

if ($provider -eq 'VertexFirewallProvider' -and $resource -eq 'WINDOWS_FIREWALL_RULE') {
    $executorPath = $FirewallExecutor
    $mapped = $true
}
else {
    $guards.Add("PROVIDER_NOT_MAPPED:$provider/$resource")
}

Write-Host "  Provider Mapped : $mapped"
Write-Host "  Executor        : $executorPath"

if ($mapped -and -not (Test-Path -LiteralPath $executorPath -PathType Leaf)) {
    $guards.Add("EXECUTOR_MISSING:$executorPath")
}

# ------------------------------------------------------------
# Live gateway preconditions
# ------------------------------------------------------------
Write-Host ''
Write-Host '[3/5] GATEWAY LIVE PRE-FLIGHT' -ForegroundColor Cyan

$isAdmin = Test-VertexAdministrator
$approvalObj = Get-SafeProperty $pre 'approval' $null
$snapshotObj = Get-SafeProperty $pre 'snapshot' $null

$approvalSatisfied = [bool](Get-SafeProperty $approvalObj 'satisfied' $false)
$snapshotSatisfied = [bool](Get-SafeProperty $snapshotObj 'satisfied' $false)
$snapshotPath = [string](Get-SafeProperty $snapshotObj 'path' '')

Write-Host "  Administrator Now : $isAdmin"
Write-Host "  Approval Recorded : $approvalSatisfied"
Write-Host "  Snapshot Recorded : $snapshotSatisfied"
Write-Host "  Snapshot Path     : $snapshotPath"

if (-not $isAdmin) {
    $guards.Add('ADMIN_PRIVILEGE_REQUIRED')
}

if (-not $approvalSatisfied) {
    $guards.Add('UPSTREAM_APPROVAL_NOT_RECORDED')
}

if (-not $snapshotSatisfied) {
    $guards.Add('SNAPSHOT_NOT_SATISFIED')
}
elseif (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
    $guards.Add("SNAPSHOT_DISAPPEARED:$snapshotPath")
}

if ($Mode -eq 'Execute' -and $Approval -ne 'APPROVE-PROVIDER-INVOKE') {
    $guards.Add('GATEWAY_APPROVAL_REQUIRED')
}

if ([string]::IsNullOrWhiteSpace($CandidateId)) {
    $guards.Add('CANDIDATE_ID_REQUIRED')
}

$gatewayDecision = if ($guards.Count -eq 0) { 'ADMIT_PROVIDER' } else { 'DENY_PROVIDER' }

Write-Host "  Gateway Decision : $gatewayDecision"

if ($guards.Count -gt 0) {
    Write-Host "  Guards           : $($guards -join ' | ')"
}

# ------------------------------------------------------------
# Dry run / invoke
# ------------------------------------------------------------
Write-Host ''
Write-Host '[4/5] PROVIDER INVOCATION' -ForegroundColor Cyan

$providerExitCode = $null
$providerStatus = 'NOT_INVOKED'

if ($gatewayDecision -ne 'ADMIT_PROVIDER') {
    Write-Host '  Provider invocation denied.' -ForegroundColor Yellow
}
elseif ($Mode -eq 'DryRun') {
    Write-Host '  DRY_RUN — provider invocation authorized but not executed.' -ForegroundColor Green
    Write-Host "  Would invoke: $executorPath"
    Write-Host "  Candidate   : $CandidateId"
    $providerStatus = 'DRY_RUN_ADMITTED'
}
else {
    Write-Host '  INVOKING PROVIDER...' -ForegroundColor Yellow

    & $executorPath `
        -Mode Execute `
        -CandidateId $CandidateId `
        -Approval 'APPROVE-TXN-EXECUTE'

    $providerExitCode = $LASTEXITCODE

    if ($providerExitCode -eq 0) {
        $providerStatus = 'PROVIDER_COMMIT_GREEN'
    }
    elseif ($providerExitCode -eq 2) {
        $providerStatus = 'PROVIDER_ROLLBACK_GREEN'
    }
    else {
        $providerStatus = "PROVIDER_EXIT_$providerExitCode"
    }
}

# ------------------------------------------------------------
# Gateway receipt
# ------------------------------------------------------------
Write-Host ''
Write-Host '[5/5] GATEWAY RECEIPT' -ForegroundColor Cyan

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $CoreRoot "VERTEX_PROVIDER_INVOCATION_GATEWAY.$stamp.json"
$txt  = Join-Path $CoreRoot "VERTEX_PROVIDER_INVOCATION_GATEWAY.$stamp.txt"

$receipt = [ordered]@{
    schema = 'vertex.transaction.provider-invocation-gateway.v1'
    version = '2.7.7'
    generated_at = (Get-Date).ToString('o')

    completed_envelope = $CompletedEnvelopePath
    revalidation_receipt = $RevalidationPath

    completion_id = $completionId
    transaction_id = $transactionId
    candidate_id = $CandidateId

    provider = $provider
    resource_type = $resource
    operation = $operation

    mode = $Mode
    gateway_decision = $gatewayDecision
    guards = @($guards)

    provider_mapping = [ordered]@{
        mapped = $mapped
        executor_path = $executorPath
    }

    invocation = [ordered]@{
        status = $providerStatus
        exit_code = $providerExitCode
    }

    safety = [ordered]@{
        one_provider_only = $true
        unsupported_provider_deny = $true
        explicit_gateway_approval_required = $true
        accepted_handoff_required = $true
    }
}

$receipt | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX PROVIDER INVOCATION GATEWAY V2.7.7',
    '============================================================',
    " Completion ID     : $completionId",
    " Transaction ID    : $transactionId",
    " Candidate ID      : $CandidateId",
    " Provider          : $provider",
    " Resource          : $resource",
    " Mode              : $Mode",
    " Gateway Decision  : $gatewayDecision",
    " Provider Status   : $providerStatus",
    " Provider ExitCode : $providerExitCode",
    '',
    " Guards            : $(if($guards.Count){$guards -join ', '}else{'NONE'})",
    '',
    " JSON              : $json",
    " TXT               : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

$color = if ($gatewayDecision -eq 'ADMIT_PROVIDER') { 'Green' } else { 'Red' }

Write-Host "  JSON   : $json"
Write-Host "  TXT    : $txt"

Write-Host ''
Write-Host '============================================================' -ForegroundColor $color
Write-Host " V2.7.7 PROVIDER INVOCATION GATEWAY : $gatewayDecision" -ForegroundColor $color
Write-Host " Provider Status : $providerStatus"
Write-Host '============================================================' -ForegroundColor $color
