#requires -Version 7.0
<#
VERTEX ENV-2 V2.8 — UNIFIED TRANSACTION ORCHESTRATOR
SEQUENTIAL STAGE EXECUTION / FAIL-CLOSED / PROVIDER EXECUTION GATED

PURPOSE
  Orchestrate the proven Vertex Transaction Core stages in one controlled flow.

PIPELINE
  1. Provider Router
  2. Typed Dispatch
  3. Provider Contract Validation
  4. Preconditions Resolver
  5. Completed Dispatch Revalidation
  6. Idempotency Guard
  7. Canonical Execution Identity
  8. Transaction Lineage
  9. Gateway Lineage Enforcement
 10. Provider Invocation Gateway

DEFAULT
  DryRun only.
  Provider execution occurs only with:
    -Mode Execute
    -Approval "APPROVE-VTC-ORCHESTRATE"

FAIL-CLOSED
  Any stage failure/hold/deny stops downstream execution.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(
        'WINDOWS_FIREWALL_RULE',
        'WINDOWS_REGISTRY',
        'WINDOWS_SERVICE',
        'WINDOWS_ENVIRONMENT',
        'WINDOWS_SCHEDULED_TASK',
        'WINDOWS_CERTIFICATE'
    )]
    [string]$ResourceType,

    [ValidateSet('OBSERVE','SNAPSHOT','VERIFY','EXECUTE','ROLLBACK')]
    [string]$Operation = 'EXECUTE',

    [string]$CandidateId = '',

    [ValidateSet('DryRun','Execute')]
    [string]$Mode = 'DryRun',

    [ValidateSet('LOW','MEDIUM','HIGH','CRITICAL')]
    [string]$MaxRisk = 'HIGH',

    [bool]$RequireRollback = $true,

    [string]$Approval = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StartupRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$ReportRoot  = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$CoreRoot    = Join-Path $ReportRoot '_transaction_core'

$Scripts = [ordered]@{
    Router = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_2_PROVIDER_ROUTER_EXECUTION_ADMISSION_CONTROL.ps1'
    Dispatch = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_3_TRANSACTION_DISPATCH_TYPED_HANDOFF.ps1'
    Validator = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_4_PROVIDER_INVOCATION_CONTRACT_VALIDATOR.ps1'
    Preconditions = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_5_PRECONDITIONS_RESOLVER_DISPATCH_COMPLETION.ps1'
    Revalidation = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_6_COMPLETED_DISPATCH_CONTRACT_REVALIDATION.ps1'
    Idempotency = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_9_IDEMPOTENCY_GUARD_LEDGER_SCHEMA_SAFE.ps1'
    Canonical = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_10_EVIDENCE_DEDUP_CANONICAL_EXECUTION_IDENTITY.ps1'
    Lineage = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_11_TRANSACTION_LINEAGE_SUPERSESSION_RESOLVER.ps1'
    Enforcement = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_12_GATEWAY_LINEAGE_ENFORCEMENT.ps1'
    Gateway = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_7_PROVIDER_INVOCATION_GATEWAY.ps1'
}

function Get-SafeProperty {
    param([AllowNull()]$Object,[Parameter(Mandatory)][string]$Name,$Default=$null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Require-Script {
    param([string]$Path,[string]$Name)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required stage script missing: $Name -> $Path"
    }
}

function Get-LatestJson {
    param([string]$Root,[string]$Filter,[bool]$Recurse=$false)
    $params = @{
        LiteralPath = $Root
        Filter = $Filter
        File = $true
        ErrorAction = 'SilentlyContinue'
    }
    if ($Recurse) { $params['Recurse'] = $true }

    return Get-ChildItem @params |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Read-Json {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
}

function Add-StageResult {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Stage,
        [string]$Status,
        [string]$Artifact,
        [string]$Detail
    )
    $List.Add([pscustomobject][ordered]@{
        stage = $Stage
        status = $Status
        artifact = $Artifact
        detail = $Detail
        at = (Get-Date).ToString('o')
    })
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.8 — UNIFIED TRANSACTION ORCHESTRATOR' -ForegroundColor Magenta
Write-Host ' ROUTE -> DISPATCH -> VALIDATE -> LINEAGE -> GATEWAY' -ForegroundColor Magenta
Write-Host ' FAIL-CLOSED / PROVIDER EXECUTION GATED' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

foreach ($name in $Scripts.Keys) {
    Require-Script -Path $Scripts[$name] -Name $name
}

if ($Mode -eq 'Execute' -and $Approval -ne 'APPROVE-VTC-ORCHESTRATE') {
    throw 'Execute mode requires -Approval "APPROVE-VTC-ORCHESTRATE".'
}

$runId = 'VORCH-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$stageResults = [System.Collections.Generic.List[object]]::new()
$pipelineStatus = 'RUNNING'
$stopReason = ''

Write-Host "Run ID        : $runId"
Write-Host "Resource      : $ResourceType"
Write-Host "Operation     : $Operation"
Write-Host "Candidate     : $CandidateId"
Write-Host "Mode          : $Mode"

# ------------------------------------------------------------
# 1 ROUTER
# ------------------------------------------------------------
Write-Host ''
Write-Host '[1/10] PROVIDER ROUTER' -ForegroundColor Cyan

& $Scripts.Router `
    -ResourceType $ResourceType `
    -Operation $Operation `
    -MaxRisk $MaxRisk `
    -RequireRollback $RequireRollback

$routerFile = Get-LatestJson -Root $CoreRoot -Filter 'VERTEX_PROVIDER_ROUTER_DECISION.*.json'
if (-not $routerFile) { throw 'Router output missing.' }
$router = Read-Json $routerFile.FullName
$routerDecision = [string](Get-SafeProperty (Get-SafeProperty $router 'admission' $null) 'decision' 'DENY')

Add-StageResult $stageResults 'ROUTER' $routerDecision $routerFile.FullName 'Provider routing completed.'

if ($routerDecision -eq 'DENY') {
    $pipelineStatus = 'STOPPED_DENY'
    $stopReason = 'Router denied request.'
}

# ------------------------------------------------------------
# 2 DISPATCH
# ------------------------------------------------------------
if ($pipelineStatus -eq 'RUNNING') {
    Write-Host ''
    Write-Host '[2/10] TYPED DISPATCH' -ForegroundColor Cyan

    & $Scripts.Dispatch `
        -RouterDecisionPath $routerFile.FullName `
        -CandidateId $CandidateId

    $dispatchFile = Get-LatestJson -Root $CoreRoot -Filter 'VERTEX_TRANSACTION_DISPATCH.VDSP-*.json'
    if (-not $dispatchFile) { throw 'Dispatch output missing.' }
    $dispatch = Read-Json $dispatchFile.FullName
    $dispatchState = [string](Get-SafeProperty (Get-SafeProperty $dispatch 'admission' $null) 'dispatch_state' 'DENIED')

    Add-StageResult $stageResults 'DISPATCH' $dispatchState $dispatchFile.FullName 'Typed handoff created.'

    if ($dispatchState -eq 'DENIED') {
        $pipelineStatus = 'STOPPED_DENY'
        $stopReason = 'Dispatch denied.'
    }
}

# ------------------------------------------------------------
# 3 VALIDATOR
# ------------------------------------------------------------
if ($pipelineStatus -eq 'RUNNING') {
    Write-Host ''
    Write-Host '[3/10] PROVIDER CONTRACT VALIDATION' -ForegroundColor Cyan

    $latestEnvelope = Get-LatestJson -Root (Join-Path $CoreRoot '_dispatch') -Filter 'dispatch_envelope.json' -Recurse $true
    if (-not $latestEnvelope) { throw 'Dispatch envelope missing.' }

    & $Scripts.Validator `
        -DispatchEnvelopePath $latestEnvelope.FullName

    $validationFile = Get-LatestJson -Root $CoreRoot -Filter 'VERTEX_PROVIDER_CONTRACT_VALIDATION.*.json'
    if (-not $validationFile) { throw 'Validation output missing.' }
    $validation = Read-Json $validationFile.FullName
    $validationDecision = [string](Get-SafeProperty (Get-SafeProperty $validation 'validation' $null) 'decision' 'REJECT')

    Add-StageResult $stageResults 'CONTRACT_VALIDATION' $validationDecision $validationFile.FullName 'Provider contract checked.'

    if ($validationDecision -eq 'REJECT') {
        $pipelineStatus = 'STOPPED_REJECT'
        $stopReason = 'Provider contract rejected.'
    }
}

# ------------------------------------------------------------
# 4 PRECONDITIONS
# ------------------------------------------------------------
if ($pipelineStatus -eq 'RUNNING') {
    Write-Host ''
    Write-Host '[4/10] PRECONDITIONS RESOLVER' -ForegroundColor Cyan

    $approvalToken = if ($Mode -eq 'Execute') { 'APPROVE-TXN-EXECUTE' } else { '' }

    & $Scripts.Preconditions `
        -ApprovalToken $approvalToken

    $completionFile = Get-LatestJson -Root $CoreRoot -Filter 'VERTEX_DISPATCH_COMPLETION.VDSPC-*.json'
    if (-not $completionFile) { throw 'Dispatch completion output missing.' }
    $completion = Read-Json $completionFile.FullName
    $completionState = [string](Get-SafeProperty (Get-SafeProperty $completion 'admission' $null) 'completed_dispatch_state' 'DENIED')

    Add-StageResult $stageResults 'PRECONDITIONS' $completionState $completionFile.FullName 'Preconditions resolved.'

    if ($completionState -eq 'DENIED') {
        $pipelineStatus = 'STOPPED_DENY'
        $stopReason = 'Preconditions denied.'
    }
    elseif ($completionState -eq 'HOLD_FOR_PRECONDITION') {
        $pipelineStatus = 'STOPPED_HOLD'
        $stopReason = 'Preconditions still unresolved.'
    }
}

# ------------------------------------------------------------
# 5 REVALIDATION
# ------------------------------------------------------------
if ($pipelineStatus -eq 'RUNNING') {
    Write-Host ''
    Write-Host '[5/10] COMPLETED DISPATCH REVALIDATION' -ForegroundColor Cyan

    & $Scripts.Revalidation

    $revalFile = Get-LatestJson -Root $CoreRoot -Filter 'VERTEX_COMPLETED_DISPATCH_REVALIDATION.*.json'
    if (-not $revalFile) { throw 'Revalidation output missing.' }
    $reval = Read-Json $revalFile.FullName
    $revalDecision = [string](Get-SafeProperty $reval 'decision' 'REJECT')

    Add-StageResult $stageResults 'REVALIDATION' $revalDecision $revalFile.FullName 'Completed dispatch revalidated.'

    if ($revalDecision -eq 'REJECT') {
        $pipelineStatus = 'STOPPED_REJECT'
        $stopReason = 'Completed dispatch rejected.'
    }
    elseif ($revalDecision -eq 'HOLD') {
        $pipelineStatus = 'STOPPED_HOLD'
        $stopReason = 'Completed dispatch held.'
    }
}

# ------------------------------------------------------------
# 6 IDEMPOTENCY
# ------------------------------------------------------------
if ($pipelineStatus -eq 'RUNNING') {
    Write-Host ''
    Write-Host '[6/10] IDEMPOTENCY GUARD' -ForegroundColor Cyan

    & $Scripts.Idempotency `
        -CandidateId $CandidateId

    $idemFile = Get-LatestJson -Root $CoreRoot -Filter 'VERTEX_IDEMPOTENCY_GUARD.*.json'
    if (-not $idemFile) { throw 'Idempotency output missing.' }
    $idem = Read-Json $idemFile.FullName
    $idemDecision = [string](Get-SafeProperty $idem 'decision' 'HOLD_IDENTITY_AMBIGUOUS')

    Add-StageResult $stageResults 'IDEMPOTENCY' $idemDecision $idemFile.FullName 'Duplicate execution check completed.'

    if ($idemDecision -eq 'DENY_ALREADY_COMMITTED') {
        $pipelineStatus = 'STOPPED_DENY'
        $stopReason = 'Transaction already committed.'
    }
    elseif ($idemDecision -like 'HOLD*') {
        $pipelineStatus = 'STOPPED_HOLD'
        $stopReason = 'Idempotency identity ambiguous.'
    }
}

# ------------------------------------------------------------
# 7 CANONICALIZATION
# ------------------------------------------------------------
if ($pipelineStatus -eq 'RUNNING') {
    Write-Host ''
    Write-Host '[7/10] CANONICAL EXECUTION IDENTITY' -ForegroundColor Cyan

    & $Scripts.Canonical `
        -CandidateId $CandidateId

    $canonFile = Get-LatestJson -Root $CoreRoot -Filter 'VERTEX_CANONICAL_EXECUTION_IDENTITY.*.json'
    if (-not $canonFile) { throw 'Canonical identity output missing.' }
    $canon = Read-Json $canonFile.FullName
    $count = [int](Get-SafeProperty $canon 'canonical_execution_count' 0)

    $canonStatus = if ($count -gt 0) { 'GREEN' } else { 'HOLD_NO_FACTS' }
    Add-StageResult $stageResults 'CANONICAL_IDENTITY' $canonStatus $canonFile.FullName "Canonical executions: $count"

    if ($count -eq 0) {
        $pipelineStatus = 'STOPPED_HOLD'
        $stopReason = 'No canonical execution facts.'
    }
}

# ------------------------------------------------------------
# 8 LINEAGE
# ------------------------------------------------------------
if ($pipelineStatus -eq 'RUNNING') {
    Write-Host ''
    Write-Host '[8/10] TRANSACTION LINEAGE' -ForegroundColor Cyan

    & $Scripts.Lineage `
        -CandidateId $CandidateId `
        -ResourceType $ResourceType `
        -Operation $Operation

    $lineageFile = Get-LatestJson -Root $CoreRoot -Filter 'VERTEX_TRANSACTION_LINEAGE.*.json'
    if (-not $lineageFile) { throw 'Lineage output missing.' }
    $lineage = Read-Json $lineageFile.FullName

    Add-StageResult $stageResults 'LINEAGE' 'GREEN' $lineageFile.FullName 'Transaction lineage resolved.'
}

# ------------------------------------------------------------
# 9 ENFORCEMENT
# ------------------------------------------------------------
if ($pipelineStatus -eq 'RUNNING') {
    Write-Host ''
    Write-Host '[9/10] GATEWAY LINEAGE ENFORCEMENT' -ForegroundColor Cyan

    & $Scripts.Enforcement `
        -CandidateId $CandidateId

    $enforcementFile = Get-LatestJson -Root $CoreRoot -Filter 'VERTEX_GATEWAY_LINEAGE_ENFORCEMENT.*.json'
    if (-not $enforcementFile) { throw 'Enforcement output missing.' }
    $enforcement = Read-Json $enforcementFile.FullName
    $enforcementDecision = [string](Get-SafeProperty $enforcement 'decision' 'HOLD')

    Add-StageResult $stageResults 'LINEAGE_ENFORCEMENT' $enforcementDecision $enforcementFile.FullName 'Gateway lineage enforcement completed.'

    if ($enforcementDecision -ne 'CONTINUE_TO_GATEWAY') {
        $pipelineStatus = if ($enforcementDecision -like 'DENY*') { 'STOPPED_DENY' } else { 'STOPPED_HOLD' }
        $stopReason = "Gateway lineage enforcement: $enforcementDecision"
    }
}

# ------------------------------------------------------------
# 10 GATEWAY
# ------------------------------------------------------------
if ($pipelineStatus -eq 'RUNNING') {
    Write-Host ''
    Write-Host '[10/10] PROVIDER INVOCATION GATEWAY' -ForegroundColor Cyan

    $gatewayMode = if ($Mode -eq 'Execute') { 'Execute' } else { 'DryRun' }
    $gatewayApproval = if ($Mode -eq 'Execute') { 'APPROVE-PROVIDER-INVOKE' } else { '' }

    & $Scripts.Gateway `
        -Mode $gatewayMode `
        -CandidateId $CandidateId `
        -Approval $gatewayApproval

    $gatewayFile = Get-LatestJson -Root $CoreRoot -Filter 'VERTEX_PROVIDER_INVOCATION_GATEWAY.*.json'
    if (-not $gatewayFile) { throw 'Gateway output missing.' }
    $gateway = Read-Json $gatewayFile.FullName
    $gatewayDecision = [string](Get-SafeProperty $gateway 'gateway_decision' 'DENY_PROVIDER')
    $invoke = Get-SafeProperty $gateway 'invocation' $null
    $providerStatus = [string](Get-SafeProperty $invoke 'status' 'NOT_INVOKED')

    Add-StageResult $stageResults 'GATEWAY' $gatewayDecision $gatewayFile.FullName $providerStatus

    if ($gatewayDecision -eq 'ADMIT_PROVIDER') {
        if ($Mode -eq 'DryRun') {
            $pipelineStatus = 'DRY_RUN_GREEN'
        }
        elseif ($providerStatus -eq 'PROVIDER_COMMIT_GREEN') {
            $pipelineStatus = 'EXECUTION_COMMIT_GREEN'
        }
        elseif ($providerStatus -eq 'PROVIDER_ROLLBACK_GREEN') {
            $pipelineStatus = 'EXECUTION_ROLLBACK_GREEN'
        }
        else {
            $pipelineStatus = 'EXECUTION_REVIEW_REQUIRED'
        }
    }
    else {
        $pipelineStatus = 'STOPPED_DENY'
        $stopReason = 'Gateway denied provider invocation.'
    }
}

if ($pipelineStatus -eq 'RUNNING') {
    $pipelineStatus = 'COMPLETED_NO_GATEWAY'
}

# ------------------------------------------------------------
# FINAL RECEIPT
# ------------------------------------------------------------
Write-Host ''
Write-Host '============================================================'
Write-Host ' VERTEX UNIFIED ORCHESTRATION RESULT'
Write-Host '============================================================'
Write-Host " Run ID        : $runId"
Write-Host " Status        : $pipelineStatus"
Write-Host " Stop Reason   : $stopReason"
Write-Host " Stages        : $($stageResults.Count)"

foreach ($s in $stageResults) {
    Write-Host "  [$($s.status)] $($s.stage)"
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $CoreRoot "VERTEX_UNIFIED_TRANSACTION_ORCHESTRATION.$stamp.json"
$txt  = Join-Path $CoreRoot "VERTEX_UNIFIED_TRANSACTION_ORCHESTRATION.$stamp.txt"

$receipt = [ordered]@{
    schema = 'vertex.transaction.unified-orchestration.v1'
    version = '2.8'
    run_id = $runId
    generated_at = (Get-Date).ToString('o')
    request = [ordered]@{
        resource_type = $ResourceType
        operation = $Operation
        candidate_id = $CandidateId
        mode = $Mode
        max_risk = $MaxRisk
        require_rollback = $RequireRollback
    }
    status = $pipelineStatus
    stop_reason = $stopReason
    stages = @($stageResults)
    safety = [ordered]@{
        fail_closed = $true
        provider_execution_only_after_all_gates = $true
        explicit_execute_approval_required = $true
    }
}

$receipt | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX UNIFIED TRANSACTION ORCHESTRATOR V2.8',
    '============================================================',
    " Run ID      : $runId",
    " Resource    : $ResourceType",
    " Operation   : $Operation",
    " Candidate   : $CandidateId",
    " Mode        : $Mode",
    " Status      : $pipelineStatus",
    " Stop Reason : $stopReason",
    '',
    $(foreach ($s in $stageResults) {
        " $($s.stage) | $($s.status) | $($s.detail)"
    }),
    '',
    " JSON : $json",
    " TXT  : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

$color = if ($pipelineStatus -in @('DRY_RUN_GREEN','EXECUTION_COMMIT_GREEN','EXECUTION_ROLLBACK_GREEN')) {
    'Green'
} elseif ($pipelineStatus -like 'STOPPED_HOLD*') {
    'Yellow'
} else {
    'Red'
}

Write-Host ''
Write-Host " JSON : $json"
Write-Host " TXT  : $txt"
Write-Host '============================================================' -ForegroundColor $color
Write-Host " V2.8 ORCHESTRATOR : $pipelineStatus" -ForegroundColor $color
Write-Host '============================================================' -ForegroundColor $color
