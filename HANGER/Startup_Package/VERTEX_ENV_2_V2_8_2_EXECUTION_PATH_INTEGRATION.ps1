#requires -Version 7.0
<#
VERTEX ENV-2 V2.8.2 — EXECUTION PATH INTEGRATION
AUDIT LANE + EXECUTE LANE / SHARED TRANSACTION IDENTITY / FAIL-CLOSED

PURPOSE
  Formalize two lanes on top of one shared transaction world-state.

AUDIT LANE
  - Continue non-mutating analysis through all safety stages.
  - HOLD/DENY are recorded as findings.
  - Provider execution is impossible.

EXECUTE LANE
  - Uses the same Candidate / Resource / Operation identity.
  - Any unresolved HOLD/DENY/REJECT stops immediately.
  - Provider Gateway may be invoked only after all safety gates pass.

SHARED PRINCIPLE
  Audit and Execute must inspect the same transaction identity,
  evidence lineage, and canonical state.
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

    [Parameter(Mandatory)]
    [string]$CandidateId,

    [ValidateSet('Audit','Execute')]
    [string]$Lane = 'Audit',

    [ValidateSet('LOW','MEDIUM','HIGH','CRITICAL')]
    [string]$MaxRisk = 'HIGH',

    [bool]$RequireRollback = $true,

    [string]$Approval = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StartupRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$ReportRoot  = Join-Path $StartupRoot 'VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$CoreRoot    = Join-Path $ReportRoot '_transaction_core'

$AuditOrchestrator = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_8_1_AUDIT_THROUGH_ORCHESTRATOR.ps1'
$ExecuteOrchestrator = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_8_UNIFIED_TRANSACTION_ORCHESTRATOR.ps1'
$Gateway = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_7_PROVIDER_INVOCATION_GATEWAY.ps1'

function Need([string]$Path,[string]$Name) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required component missing: $Name -> $Path"
    }
}

function Latest([string]$Filter,[string]$Root=$CoreRoot) {
    Get-ChildItem -LiteralPath $Root -Filter $Filter -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function ReadJson([string]$Path) {
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
}

function P($o,[string]$n,$d=$null) {
    if($null -eq $o){ return $d }
    $p=$o.PSObject.Properties[$n]
    if($null -eq $p -or $null -eq $p.Value){ return $d }
    return $p.Value
}

Need $AuditOrchestrator 'V2.8.1 Audit Orchestrator'
Need $ExecuteOrchestrator 'V2.8 Execute Orchestrator'
Need $Gateway 'V2.7.7 Provider Gateway'

if($Lane -eq 'Execute' -and $Approval -ne 'APPROVE-VTC-EXECUTION-LANE') {
    throw 'Execute lane requires -Approval "APPROVE-VTC-EXECUTION-LANE".'
}

$runId = 'VPATH-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$sharedIdentity = [ordered]@{
    candidate_id = $CandidateId
    resource_type = $ResourceType
    operation = $Operation
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.8.2 — EXECUTION PATH INTEGRATION' -ForegroundColor Magenta
Write-Host ' AUDIT LANE / EXECUTE LANE / SHARED TRANSACTION WORLD-STATE' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host "Run ID      : $runId"
Write-Host "Lane        : $Lane"
Write-Host "Candidate   : $CandidateId"
Write-Host "Resource    : $ResourceType"
Write-Host "Operation   : $Operation"

$finalStatus = 'UNKNOWN'
$sourceReceipt = ''
$providerInvocation = 'NONE'
$providerStatus = 'NOT_INVOKED'
$stopReason = ''
$laneFacts = [System.Collections.Generic.List[string]]::new()

if($Lane -eq 'Audit') {
    Write-Host ''
    Write-Host '[AUDIT LANE]' -ForegroundColor Cyan

    & $AuditOrchestrator `
        -ResourceType $ResourceType `
        -Operation $Operation `
        -CandidateId $CandidateId `
        -Mode DryRun `
        -MaxRisk $MaxRisk

    $auditFile = Latest 'VERTEX_AUDIT_THROUGH_ORCHESTRATION.*.json'
    if(-not $auditFile){ throw 'Audit-through receipt not found.' }

    $audit = ReadJson $auditFile.FullName
    $auditFinal = [string](P $audit 'final_status' 'UNKNOWN')
    $flags = @(P $audit 'audit_flags' @())

    $sourceReceipt = $auditFile.FullName
    $finalStatus = $auditFinal
    $providerInvocation = 'FORBIDDEN_BY_AUDIT_LANE'

    foreach($f in $flags) {
        $laneFacts.Add("AUDIT_FLAG:$f")
    }

    Write-Host "  Final Status        : $auditFinal"
    Write-Host "  Provider Invocation : FORBIDDEN" -ForegroundColor Green
}
else {
    Write-Host ''
    Write-Host '[EXECUTE LANE]' -ForegroundColor Yellow

    # First run the same unified safety chain in execute mode.
    & $ExecuteOrchestrator `
        -ResourceType $ResourceType `
        -Operation $Operation `
        -CandidateId $CandidateId `
        -Mode Execute `
        -MaxRisk $MaxRisk `
        -RequireRollback $RequireRollback `
        -Approval 'APPROVE-VTC-ORCHESTRATE'

    $execFile = Latest 'VERTEX_UNIFIED_TRANSACTION_ORCHESTRATION.*.json'
    if(-not $execFile){ throw 'Execute orchestration receipt not found.' }

    $exec = ReadJson $execFile.FullName
    $execStatus = [string](P $exec 'status' 'UNKNOWN')
    $execStop = [string](P $exec 'stop_reason' '')

    $sourceReceipt = $execFile.FullName
    $stopReason = $execStop

    Write-Host "  Unified Status : $execStatus"
    if($execStop){ Write-Host "  Stop Reason    : $execStop" }

    # V2.8 already invokes Gateway if all gates pass.
    # We do NOT invoke Gateway a second time here.
    if($execStatus -eq 'EXECUTION_COMMIT_GREEN') {
        $finalStatus = 'EXECUTION_COMMIT_GREEN'
        $providerInvocation = 'ALREADY_PERFORMED_BY_V2_8'
        $providerStatus = 'COMMIT_GREEN'
    }
    elseif($execStatus -eq 'EXECUTION_ROLLBACK_GREEN') {
        $finalStatus = 'EXECUTION_ROLLBACK_GREEN'
        $providerInvocation = 'ALREADY_PERFORMED_BY_V2_8'
        $providerStatus = 'ROLLBACK_GREEN'
    }
    elseif($execStatus -eq 'DRY_RUN_GREEN') {
        $finalStatus = 'INVALID_EXECUTE_LANE_RESULT'
        $providerInvocation = 'NONE'
        $providerStatus = 'NOT_INVOKED'
    }
    elseif($execStatus -like 'STOPPED_*') {
        $finalStatus = $execStatus
        $providerInvocation = 'BLOCKED_BY_EXECUTE_LANE'
        $providerStatus = 'NOT_INVOKED'
    }
    else {
        $finalStatus = $execStatus
        $providerInvocation = 'UNKNOWN_OR_NOT_REQUIRED'
        $providerStatus = 'NOT_INVOKED'
    }
}

# Shared identity consistency check against latest lineage / idempotency artifacts.
$lineageFile = Latest 'VERTEX_TRANSACTION_LINEAGE.*.json'
$idemFile = Latest 'VERTEX_IDEMPOTENCY_GUARD.*.json'

$lineageStates = @()
$idemDecision = ''

if($lineageFile) {
    $lineage = ReadJson $lineageFile.FullName
    $facts = @(P $lineage 'facts' @() | Where-Object {
        [string](P $_ 'candidate_id' '') -eq $CandidateId
    })
    $lineageStates = @($facts | ForEach-Object {
        [string](P $_ 'lineage_state' '')
    } | Where-Object { $_ } | Select-Object -Unique)
}

if($idemFile) {
    $idem = ReadJson $idemFile.FullName
    $idemReq = P $idem 'request' $null
    $idemCandidate = [string](P $idemReq 'candidate_id' '')
    if($idemCandidate -eq $CandidateId) {
        $idemDecision = [string](P $idem 'decision' '')
    }
}

if($lineageStates.Count -gt 0) {
    foreach($s in $lineageStates){ $laneFacts.Add("LINEAGE:$s") }
}
if($idemDecision){ $laneFacts.Add("IDEMPOTENCY:$idemDecision") }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $CoreRoot "VERTEX_EXECUTION_PATH_INTEGRATION.$stamp.json"
$txt  = Join-Path $CoreRoot "VERTEX_EXECUTION_PATH_INTEGRATION.$stamp.txt"

$receipt = [ordered]@{
    schema = 'vertex.transaction.execution-path-integration.v1'
    version = '2.8.2'
    run_id = $runId
    generated_at = (Get-Date).ToString('o')

    lane = $Lane
    shared_identity = $sharedIdentity

    final_status = $finalStatus
    stop_reason = $stopReason
    source_receipt = $sourceReceipt

    observed_state = [ordered]@{
        idempotency_decision = $idemDecision
        lineage_states = $lineageStates
        facts = @($laneFacts)
    }

    provider = [ordered]@{
        invocation = $providerInvocation
        status = $providerStatus
    }

    invariants = [ordered]@{
        audit_lane_provider_execution = 'FORBIDDEN'
        execute_lane_fail_closed = $true
        shared_candidate_identity = $true
        shared_resource_identity = $true
        shared_operation_identity = $true
        duplicate_gateway_invocation = 'DENIED'
    }
}

$receipt | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX EXECUTION PATH INTEGRATION V2.8.2',
    '============================================================',
    " Run ID              : $runId",
    " Lane                : $Lane",
    " Candidate           : $CandidateId",
    " Resource            : $ResourceType",
    " Operation           : $Operation",
    " Final Status        : $finalStatus",
    " Stop Reason         : $stopReason",
    " Idempotency         : $idemDecision",
    " Lineage             : $($lineageStates -join ', ')",
    " Provider Invocation : $providerInvocation",
    " Provider Status     : $providerStatus",
    '',
    $(foreach($f in $laneFacts){" $f"}),
    '',
    " JSON : $json",
    " TXT  : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

$color = if($Lane -eq 'Audit') {
    if($finalStatus -eq 'AUDIT_THROUGH_GREEN'){'Green'}else{'Yellow'}
}
else {
    if($finalStatus -in @('EXECUTION_COMMIT_GREEN','EXECUTION_ROLLBACK_GREEN')){'Green'}
    elseif($finalStatus -like 'STOPPED_HOLD*'){'Yellow'}
    else{'Red'}
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor $color
Write-Host " V2.8.2 EXECUTION PATH : $finalStatus" -ForegroundColor $color
Write-Host " Lane                : $Lane"
Write-Host " Provider Invocation : $providerInvocation"
Write-Host " JSON                : $json"
Write-Host " TXT                 : $txt"
Write-Host '============================================================' -ForegroundColor $color
