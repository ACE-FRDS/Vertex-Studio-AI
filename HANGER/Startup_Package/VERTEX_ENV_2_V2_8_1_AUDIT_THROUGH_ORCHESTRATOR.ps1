#requires -Version 7.0
<#
VERTEX ENV-2 V2.8.1 — AUDIT-THROUGH ORCHESTRATOR
DRYRUN CONTINUES THROUGH NON-MUTATING SAFETY ANALYSIS
EXECUTE REMAINS FAIL-CLOSED

KEY RULE
  DryRun:
    unresolved runtime preconditions are recorded, not bypassed for execution.
    provider invocation is NEVER performed.
    analysis continues through idempotency/canonical/lineage/enforcement.

  Execute:
    unresolved preconditions STOP immediately.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('WINDOWS_FIREWALL_RULE','WINDOWS_REGISTRY','WINDOWS_SERVICE',
                 'WINDOWS_ENVIRONMENT','WINDOWS_SCHEDULED_TASK','WINDOWS_CERTIFICATE')]
    [string]$ResourceType,

    [ValidateSet('OBSERVE','SNAPSHOT','VERIFY','EXECUTE','ROLLBACK')]
    [string]$Operation = 'EXECUTE',

    [Parameter(Mandatory)]
    [string]$CandidateId,

    [ValidateSet('DryRun','Execute')]
    [string]$Mode = 'DryRun',

    [ValidateSet('LOW','MEDIUM','HIGH','CRITICAL')]
    [string]$MaxRisk = 'HIGH',

    [string]$Approval = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StartupRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$ReportRoot  = Join-Path $StartupRoot 'VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$CoreRoot    = Join-Path $ReportRoot '_transaction_core'

$S = @{
    Router        = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_2_PROVIDER_ROUTER_EXECUTION_ADMISSION_CONTROL.ps1'
    Dispatch      = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_3_TRANSACTION_DISPATCH_TYPED_HANDOFF.ps1'
    Validator     = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_4_PROVIDER_INVOCATION_CONTRACT_VALIDATOR.ps1'
    Preconditions = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_5_PRECONDITIONS_RESOLVER_DISPATCH_COMPLETION.ps1'
    Revalidation  = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_6_COMPLETED_DISPATCH_CONTRACT_REVALIDATION.ps1'
    Idempotency   = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_9_IDEMPOTENCY_GUARD_LEDGER_SCHEMA_SAFE.ps1'
    Canonical     = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_10_EVIDENCE_DEDUP_CANONICAL_EXECUTION_IDENTITY.ps1'
    Lineage       = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_11_TRANSACTION_LINEAGE_SUPERSESSION_RESOLVER.ps1'
    Enforcement   = Join-Path $StartupRoot 'VERTEX_ENV_2_V2_7_12_GATEWAY_LINEAGE_ENFORCEMENT.ps1'
}

function Need([string]$Name) {
    if (-not (Test-Path -LiteralPath $S[$Name] -PathType Leaf)) {
        throw "Missing required stage: $Name -> $($S[$Name])"
    }
}
function Latest([string]$Filter,[string]$Root=$CoreRoot,[switch]$Recurse) {
    $p=@{LiteralPath=$Root;Filter=$Filter;File=$true;ErrorAction='SilentlyContinue'}
    if($Recurse){$p.Recurse=$true}
    Get-ChildItem @p | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
function J([string]$Path) {
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
}
function P($o,[string]$n,$d=$null) {
    if($null -eq $o){return $d}
    $x=$o.PSObject.Properties[$n]
    if($null -eq $x -or $null -eq $x.Value){return $d}
    $x.Value
}
function Record([string]$Stage,[string]$Status,[string]$Detail,[string]$Artifact='') {
    $script:Stages.Add([pscustomobject][ordered]@{
        stage=$Stage;status=$Status;detail=$Detail;artifact=$Artifact;at=(Get-Date).ToString('o')
    })
}
function Stop-ExecuteIf([bool]$Condition,[string]$Why) {
    if($Condition -and $Mode -eq 'Execute'){
        $script:Final='STOPPED_HOLD'
        $script:StopReason=$Why
        return $true
    }
    return $false
}

foreach($n in $S.Keys){ Need $n }

if($Mode -eq 'Execute' -and $Approval -ne 'APPROVE-VTC-ORCHESTRATE'){
    throw 'Execute requires -Approval "APPROVE-VTC-ORCHESTRATE".'
}

$RunId='VORCH-AUDIT-'+(Get-Date -Format 'yyyyMMdd-HHmmss')
$Stages=[System.Collections.Generic.List[object]]::new()
$Final='RUNNING'
$StopReason=''
$AuditFlags=[System.Collections.Generic.List[string]]::new()

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.8.1 — AUDIT-THROUGH ORCHESTRATOR' -ForegroundColor Magenta
Write-Host ' DRYRUN: ANALYZE THROUGH / EXECUTE: FAIL-CLOSED' -ForegroundColor Magenta
Write-Host ' PROVIDER INVOCATION IN DRYRUN: IMPOSSIBLE' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host "Run ID    : $RunId"
Write-Host "Candidate : $CandidateId"
Write-Host "Mode      : $Mode"

# 1 ROUTER
Write-Host "`n[1/9] ROUTER" -ForegroundColor Cyan
& $S.Router -ResourceType $ResourceType -Operation $Operation -MaxRisk $MaxRisk
$rf=Latest 'VERTEX_PROVIDER_ROUTER_DECISION.*.json'; if(-not $rf){throw 'Router receipt missing'}
$r=J $rf.FullName
$rd=[string](P (P $r 'admission') 'decision' (P $r 'decision' 'UNKNOWN'))
Record 'ROUTER' $rd 'Routing/admission evaluated.' $rf.FullName
if($rd -eq 'DENY'){ $Final='STOPPED_DENY'; $StopReason='Router denied request.' }

# 2 DISPATCH
if($Final -eq 'RUNNING'){
    Write-Host "`n[2/9] DISPATCH" -ForegroundColor Cyan
    & $S.Dispatch -RouterDecisionPath $rf.FullName -CandidateId $CandidateId
    $df=Latest 'VERTEX_TRANSACTION_DISPATCH.VDSP-*.json'; if(-not $df){throw 'Dispatch receipt missing'}
    $d=J $df.FullName
    $ds=[string](P (P $d 'admission') 'dispatch_state' (P $d 'dispatch_state' 'UNKNOWN'))
    Record 'DISPATCH' $ds 'Typed dispatch generated.' $df.FullName
}

# 3 CONTRACT
if($Final -eq 'RUNNING'){
    Write-Host "`n[3/9] CONTRACT VALIDATION" -ForegroundColor Cyan
    $env=Latest 'dispatch_envelope.json' (Join-Path $CoreRoot '_dispatch') -Recurse
    if(-not $env){throw 'Dispatch envelope missing'}
    & $S.Validator -DispatchEnvelopePath $env.FullName
    $vf=Latest 'VERTEX_PROVIDER_CONTRACT_VALIDATION.*.json'; if(-not $vf){throw 'Validation receipt missing'}
    $v=J $vf.FullName
    $vd=[string](P (P $v 'validation') 'decision' (P $v 'decision' 'UNKNOWN'))
    Record 'CONTRACT_VALIDATION' $vd 'Contract evaluated.' $vf.FullName
    if($vd -eq 'REJECT'){ $Final='STOPPED_REJECT'; $StopReason='Contract rejected.' }
    elseif($vd -eq 'HOLD'){
        $AuditFlags.Add('CONTRACT_HOLD')
        if(Stop-ExecuteIf $true 'Contract HOLD in Execute mode.'){}
    }
}

# 4 PRECONDITIONS
if($Final -eq 'RUNNING'){
    Write-Host "`n[4/9] PRECONDITIONS" -ForegroundColor Cyan
    $token = if($Mode -eq 'Execute'){'APPROVE-TXN-EXECUTE'}else{''}
    & $S.Preconditions -ApprovalToken $token
    $pf=Latest 'VERTEX_DISPATCH_COMPLETION.VDSPC-*.json'; if(-not $pf){throw 'Completion receipt missing'}
    $p=J $pf.FullName
    $ps=[string](P (P $p 'admission') 'completed_dispatch_state' (P $p 'decision' 'UNKNOWN'))
    Record 'PRECONDITIONS' $ps 'Runtime preconditions observed.' $pf.FullName

    if($ps -eq 'HOLD_FOR_PRECONDITION'){
        $AuditFlags.Add('RUNTIME_PRECONDITIONS_UNRESOLVED')
        if($Mode -eq 'DryRun'){
            Write-Host '  AUDIT-THROUGH: HOLD recorded; continuing non-mutating analysis.' -ForegroundColor Yellow
        } else {
            $Final='STOPPED_HOLD'; $StopReason='Runtime preconditions unresolved.'
        }
    }
}

# In DryRun, do NOT revalidate a non-ready completed dispatch as executable.
# Revalidation is represented as audit-only skipped evidence.
if($Final -eq 'RUNNING'){
    Write-Host "`n[5/9] REVALIDATION" -ForegroundColor Cyan
    if($Mode -eq 'DryRun' -and $AuditFlags -contains 'RUNTIME_PRECONDITIONS_UNRESOLVED'){
        Record 'REVALIDATION' 'AUDIT_SKIPPED_NOT_READY' 'Completed dispatch is not READY_FOR_PROVIDER; execution acceptance intentionally not synthesized.'
        Write-Host '  AUDIT_SKIPPED_NOT_READY — no false ACCEPT synthesized.' -ForegroundColor Yellow
    } else {
        & $S.Revalidation
        $rvf=Latest 'VERTEX_COMPLETED_DISPATCH_REVALIDATION.*.json'; if(-not $rvf){throw 'Revalidation receipt missing'}
        $rv=J $rvf.FullName
        $rvd=[string](P $rv 'decision' 'UNKNOWN')
        Record 'REVALIDATION' $rvd 'Live completed-dispatch revalidation.' $rvf.FullName
        if($rvd -eq 'REJECT'){ $Final='STOPPED_REJECT';$StopReason='Revalidation rejected.' }
        elseif($rvd -eq 'HOLD' -and $Mode -eq 'Execute'){ $Final='STOPPED_HOLD';$StopReason='Revalidation held.' }
    }
}

# 6 IDEMPOTENCY — analysis continues in DryRun
if($Final -eq 'RUNNING'){
    Write-Host "`n[6/9] IDEMPOTENCY" -ForegroundColor Cyan
    & $S.Idempotency -CandidateId $CandidateId
    $if=Latest 'VERTEX_IDEMPOTENCY_GUARD.*.json'; if(-not $if){throw 'Idempotency receipt missing'}
    $i=J $if.FullName
    $id=[string](P $i 'decision' 'UNKNOWN')
    Record 'IDEMPOTENCY' $id 'Committed execution identity checked.' $if.FullName

    if($id -eq 'DENY_ALREADY_COMMITTED'){
        $AuditFlags.Add('ALREADY_COMMITTED')
        if($Mode -eq 'Execute'){ $Final='STOPPED_DENY';$StopReason='Already committed.' }
    }
}

# 7 CANONICAL + LINEAGE
if($Final -eq 'RUNNING'){
    Write-Host "`n[7/9] CANONICAL IDENTITY + LINEAGE" -ForegroundColor Cyan
    & $S.Canonical -CandidateId $CandidateId
    $cf=Latest 'VERTEX_CANONICAL_EXECUTION_IDENTITY.*.json'; if(-not $cf){throw 'Canonical receipt missing'}
    Record 'CANONICAL_IDENTITY' 'GREEN' 'Canonical execution facts rebuilt.' $cf.FullName

    & $S.Lineage -CandidateId $CandidateId -ResourceType $ResourceType -Operation $Operation
    $lf=Latest 'VERTEX_TRANSACTION_LINEAGE.*.json'; if(-not $lf){throw 'Lineage receipt missing'}
    Record 'LINEAGE' 'GREEN' 'Supersession lineage resolved.' $lf.FullName
}

# 8 ENFORCEMENT
if($Final -eq 'RUNNING'){
    Write-Host "`n[8/9] LINEAGE ENFORCEMENT" -ForegroundColor Cyan
    & $S.Enforcement -CandidateId $CandidateId
    $ef=Latest 'VERTEX_GATEWAY_LINEAGE_ENFORCEMENT.*.json'; if(-not $ef){throw 'Enforcement receipt missing'}
    $e=J $ef.FullName
    $ed=[string](P $e 'decision' 'UNKNOWN')
    Record 'LINEAGE_ENFORCEMENT' $ed 'Final lineage/idempotency admission simulated.' $ef.FullName
    if($ed -like 'DENY*'){$AuditFlags.Add($ed)}
    elseif($ed -like 'HOLD*'){$AuditFlags.Add($ed)}
}

# 9 GATEWAY SIMULATION
if($Final -eq 'RUNNING'){
    Write-Host "`n[9/9] GATEWAY SIMULATION" -ForegroundColor Cyan
    $ef=Latest 'VERTEX_GATEWAY_LINEAGE_ENFORCEMENT.*.json'
    $e=J $ef.FullName
    $ed=[string](P $e 'decision' 'UNKNOWN')

    if($Mode -eq 'DryRun'){
        $gatewayDecision = if($ed -eq 'CONTINUE_TO_GATEWAY'){'WOULD_ADMIT_PROVIDER'}else{"WOULD_NOT_ADMIT_PROVIDER:$ed"}
        Record 'GATEWAY_SIMULATION' $gatewayDecision 'Provider invocation intentionally disabled in DryRun.'
        $Final='AUDIT_THROUGH_GREEN'
        Write-Host "  $gatewayDecision" -ForegroundColor Green
        Write-Host '  PROVIDER INVOCATION : NONE' -ForegroundColor Green
    } else {
        # V2.8.1 deliberately keeps real provider invocation delegated to proven V2.8/V2.7.7 path.
        # This version proves audit-through semantics without widening mutation authority.
        $Final='READY_FOR_EXECUTE_ORCHESTRATOR'
        Record 'GATEWAY_EXECUTION_HANDOFF' 'READY_FOR_EXECUTE_ORCHESTRATOR' 'Use proven execution gateway after all execute-mode gates pass.'
    }
}

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$json=Join-Path $CoreRoot "VERTEX_AUDIT_THROUGH_ORCHESTRATION.$stamp.json"
$txt =Join-Path $CoreRoot "VERTEX_AUDIT_THROUGH_ORCHESTRATION.$stamp.txt"

$receipt=[ordered]@{
    schema='vertex.transaction.audit-through-orchestration.v1'
    version='2.8.1'
    run_id=$RunId
    generated_at=(Get-Date).ToString('o')
    request=[ordered]@{
        resource_type=$ResourceType;operation=$Operation;candidate_id=$CandidateId;mode=$Mode;max_risk=$MaxRisk
    }
    final_status=$Final
    stop_reason=$StopReason
    audit_flags=@($AuditFlags)
    stages=@($Stages)
    invariants=[ordered]@{
        dryrun_provider_invocation=$false
        dryrun_system_mutation=$false
        execute_fail_closed=$true
        unresolved_preconditions_never_synthesized_as_accept=$true
    }
}
$receipt|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $json -Encoding UTF8

@(
'============================================================',
' VERTEX V2.8.1 AUDIT-THROUGH RECEIPT',
'============================================================',
" Run ID       : $RunId",
" Final Status : $Final",
" Stop Reason  : $StopReason",
" Audit Flags  : $($AuditFlags -join ', ')",
'',
$(foreach($x in $Stages){" $($x.stage) | $($x.status) | $($x.detail)"}),
'',
' PROVIDER INVOCATION : NONE IN DRYRUN',
" JSON : $json",
" TXT  : $txt",
'============================================================'
)|Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host " V2.8.1 AUDIT-THROUGH : $Final" -ForegroundColor Green
Write-Host " Audit Flags : $($AuditFlags -join ', ')"
Write-Host ' PROVIDER INVOCATION : NONE IN DRYRUN'
Write-Host " JSON : $json"
Write-Host " TXT  : $txt"
Write-Host '============================================================' -ForegroundColor Green
