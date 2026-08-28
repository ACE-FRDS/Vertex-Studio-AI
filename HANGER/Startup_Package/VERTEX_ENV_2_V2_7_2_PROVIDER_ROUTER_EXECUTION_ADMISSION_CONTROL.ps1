#requires -Version 7.0
<#
VERTEX ENV-2 V2.7.2 — PROVIDER ROUTER & EXECUTION ADMISSION CONTROL
ZERO SYSTEM MUTATION

PURPOSE
  Route a requested transaction resource type to the correct provider
  and decide whether execution should be ADMITTED, HELD, or DENIED.

INPUT MODEL
  ResourceType
  Operation
  RiskTolerance
  RequireRollback

DECISION MODEL
  Provider exists?
    -> implemented?
    -> proven?
    -> available_now?
    -> blocked_by?
    -> risk allowed?
    -> rollback ready?
    -> human gate required?
    -> ADMIT / HOLD / DENY

ZERO SYSTEM MUTATION.
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

    [ValidateSet('LOW','MEDIUM','HIGH','CRITICAL')]
    [string]$MaxRisk = 'HIGH',

    [bool]$RequireRollback = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$CoreRoot   = Join-Path $ReportRoot '_transaction_core'

if (-not (Test-Path -LiteralPath $CoreRoot)) {
    throw "Transaction core report root not found: $CoreRoot"
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

function Convert-RiskRank {
    param([string]$Risk)

    switch ($Risk) {
        'LOW'      { return 1 }
        'MEDIUM'   { return 2 }
        'HIGH'     { return 3 }
        'CRITICAL' { return 4 }
        default    { return 99 }
    }
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.7.2 — PROVIDER ROUTER' -ForegroundColor Magenta
Write-Host ' RESOURCE -> CAPABILITY -> RISK -> ADMISSION CONTROL' -ForegroundColor Magenta
Write-Host ' ZERO SYSTEM MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$capabilityFile = Get-ChildItem -LiteralPath $CoreRoot -Filter 'VERTEX_PROVIDER_CAPABILITY_MODEL.*.json' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $capabilityFile) {
    throw 'No V2.7.1 provider capability model found.'
}

$capability = Get-Content -LiteralPath $capabilityFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80
$providers = @($capability.providers)

$provider = @(
    $providers |
    Where-Object {
        [string](Get-SafeProperty -Object $_ -Name 'resource_type' -Default '') -eq $ResourceType
    }
)

if ($provider.Count -ne 1) {
    throw "Provider routing failed. ResourceType=$ResourceType Matches=$($provider.Count)"
}

$provider = $provider[0]

$providerName = [string](Get-SafeProperty -Object $provider -Name 'provider_name' -Default '')
$observeReady = [bool](Get-SafeProperty -Object $provider -Name 'observe_ready' -Default $false)
$snapshotReady = [bool](Get-SafeProperty -Object $provider -Name 'snapshot_ready' -Default $false)
$verifyReady = [bool](Get-SafeProperty -Object $provider -Name 'verify_ready' -Default $false)
$implemented = [bool](Get-SafeProperty -Object $provider -Name 'executor_implemented' -Default $false)
$proven = [bool](Get-SafeProperty -Object $provider -Name 'executor_proven' -Default $false)
$availableNow = [bool](Get-SafeProperty -Object $provider -Name 'available_now' -Default $false)
$blockedBy = @(Get-SafeProperty -Object $provider -Name 'blocked_by' -Default @())
$rollbackReady = [bool](Get-SafeProperty -Object $provider -Name 'rollback_ready' -Default $false)
$riskClass = [string](Get-SafeProperty -Object $provider -Name 'risk_class' -Default 'CRITICAL')
$lifecycle = [string](Get-SafeProperty -Object $provider -Name 'lifecycle_state' -Default '')

Write-Host ''
Write-Host '[1/3] ROUTE' -ForegroundColor Cyan
Write-Host "  Resource Type  : $ResourceType"
Write-Host "  Provider       : $providerName"
Write-Host "  Lifecycle      : $lifecycle"
Write-Host "  Operation      : $Operation"

$reasons = [System.Collections.Generic.List[string]]::new()
$guards  = [System.Collections.Generic.List[string]]::new()

# Operation readiness
$operationReady = $false

switch ($Operation) {
    'OBSERVE' {
        $operationReady = $observeReady
        if (-not $observeReady) { $guards.Add('OBSERVE_NOT_READY') }
    }

    'SNAPSHOT' {
        $operationReady = $snapshotReady
        if (-not $snapshotReady) { $guards.Add('SNAPSHOT_NOT_READY') }
    }

    'VERIFY' {
        $operationReady = $verifyReady
        if (-not $verifyReady) { $guards.Add('VERIFY_NOT_READY') }
    }

    'EXECUTE' {
        if (-not $implemented) { $guards.Add('EXECUTOR_NOT_IMPLEMENTED') }
        if (-not $proven)      { $guards.Add('EXECUTOR_NOT_PROVEN') }
        if (-not $availableNow){ $guards.Add('NOT_AVAILABLE_NOW') }

        foreach ($b in $blockedBy) {
            if ($b) { $guards.Add("BLOCKED:$b") }
        }

        $operationReady = ($implemented -and $proven -and $availableNow -and $blockedBy.Count -eq 0)
    }

    'ROLLBACK' {
        $operationReady = $rollbackReady
        if (-not $rollbackReady) { $guards.Add('ROLLBACK_NOT_READY') }
    }
}

# Risk admission
$providerRisk = Convert-RiskRank $riskClass
$allowedRisk  = Convert-RiskRank $MaxRisk
$riskAllowed = ($providerRisk -le $allowedRisk)

if ($riskAllowed) {
    $reasons.Add("Risk allowed: $riskClass <= $MaxRisk")
}
else {
    $guards.Add("RISK_EXCEEDS_POLICY:$riskClass>$MaxRisk")
}

# Rollback admission
$rollbackAllowed = $true
if ($RequireRollback -and $Operation -eq 'EXECUTE') {
    $rollbackAllowed = $rollbackReady
    if ($rollbackReady) {
        $reasons.Add('Rollback requirement satisfied.')
    }
    else {
        $guards.Add('ROLLBACK_REQUIRED_BUT_NOT_READY')
    }
}

# Human gate policy
$humanGateRequired = $false

if ($Operation -eq 'EXECUTE') {
    if ($riskClass -in @('HIGH','CRITICAL')) {
        $humanGateRequired = $true
    }

    if ($ResourceType -in @(
        'WINDOWS_FIREWALL_RULE',
        'WINDOWS_REGISTRY',
        'WINDOWS_SERVICE',
        'WINDOWS_ENVIRONMENT',
        'WINDOWS_SCHEDULED_TASK',
        'WINDOWS_CERTIFICATE'
    )) {
        $humanGateRequired = $true
    }
}

if ($humanGateRequired) {
    $reasons.Add('Human gate required by policy.')
}

# Final admission decision
$decision = 'DENY'

if ($Operation -in @('OBSERVE','SNAPSHOT','VERIFY','ROLLBACK')) {
    if ($operationReady -and $riskAllowed) {
        $decision = 'ADMIT'
    }
    elseif ($operationReady) {
        $decision = 'HOLD'
    }
}
elseif ($Operation -eq 'EXECUTE') {
    if (-not $implemented) {
        $decision = 'DENY'
    }
    elseif (-not $proven) {
        $decision = 'HOLD'
    }
    elseif (-not $riskAllowed) {
        $decision = 'DENY'
    }
    elseif (-not $rollbackAllowed) {
        $decision = 'DENY'
    }
    elseif (-not $availableNow -or $blockedBy.Count -gt 0) {
        $decision = 'HOLD'
    }
    else {
        $decision = 'ADMIT'
    }
}

Write-Host ''
Write-Host '[2/3] ADMISSION CONTROL' -ForegroundColor Cyan
Write-Host "  Implemented    : $implemented"
Write-Host "  Proven         : $proven"
Write-Host "  Available Now  : $availableNow"
Write-Host "  Risk Class     : $riskClass"
Write-Host "  Max Risk       : $MaxRisk"
Write-Host "  Risk Allowed   : $riskAllowed"
Write-Host "  Rollback Ready : $rollbackReady"
Write-Host "  Require Rollback: $RequireRollback"
Write-Host "  Human Gate     : $humanGateRequired"

if ($blockedBy.Count -gt 0) {
    Write-Host "  Blocked By     : $($blockedBy -join ', ')"
}

Write-Host ''
$color = switch ($decision) {
    'ADMIT' { 'Green' }
    'HOLD'  { 'Yellow' }
    default { 'Red' }
}

Write-Host "  DECISION       : $decision" -ForegroundColor $color

if ($reasons.Count -gt 0) {
    Write-Host "  Reasons        : $($reasons -join ' | ')"
}

if ($guards.Count -gt 0) {
    Write-Host "  Guards         : $($guards -join ' | ')"
}

# ------------------------------------------------------------
# Report
# ------------------------------------------------------------
Write-Host ''
Write-Host '[3/3] ROUTER RECEIPT' -ForegroundColor Cyan

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $CoreRoot "VERTEX_PROVIDER_ROUTER_DECISION.$stamp.json"
$txt  = Join-Path $CoreRoot "VERTEX_PROVIDER_ROUTER_DECISION.$stamp.txt"

$receipt = [ordered]@{
    schema = 'vertex.transaction.provider-router-decision.v1'
    version = '2.7.2'
    generated_at = (Get-Date).ToString('o')
    source_capability_model = $capabilityFile.FullName

    request = [ordered]@{
        resource_type = $ResourceType
        operation = $Operation
        max_risk = $MaxRisk
        require_rollback = $RequireRollback
    }

    route = [ordered]@{
        provider_name = $providerName
        lifecycle_state = $lifecycle
    }

    capability = [ordered]@{
        observe_ready = $observeReady
        snapshot_ready = $snapshotReady
        verify_ready = $verifyReady
        executor_implemented = $implemented
        executor_proven = $proven
        available_now = $availableNow
        blocked_by = $blockedBy
        rollback_ready = $rollbackReady
        risk_class = $riskClass
    }

    admission = [ordered]@{
        decision = $decision
        operation_ready = $operationReady
        risk_allowed = $riskAllowed
        rollback_allowed = $rollbackAllowed
        human_gate_required = $humanGateRequired
        reasons = @($reasons)
        guards = @($guards)
    }

    safety = [ordered]@{
        system_mutation = 'NONE'
        provider_invocation = 'NONE'
        decision_only = $true
    }
}

$receipt | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX PROVIDER ROUTER DECISION V2.7.2',
    '============================================================',
    " Resource Type      : $ResourceType",
    " Operation          : $Operation",
    " Provider           : $providerName",
    " Implemented        : $implemented",
    " Proven             : $proven",
    " Available Now      : $availableNow",
    " Risk               : $riskClass",
    " Max Risk           : $MaxRisk",
    " Rollback Ready     : $rollbackReady",
    " Human Gate         : $humanGateRequired",
    " Decision           : $decision",
    '',
    " Blocked By         : $(if($blockedBy.Count){$blockedBy -join ', '}else{'NONE'})",
    " Guards             : $(if($guards.Count){$guards -join ', '}else{'NONE'})",
    '',
    ' SYSTEM MUTATION    : NONE',
    ' PROVIDER INVOCATION: NONE',
    '',
    " JSON               : $json",
    " TXT                : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host "  JSON : $json"
Write-Host "  TXT  : $txt"

Write-Host ''
Write-Host '============================================================' -ForegroundColor $color
Write-Host " V2.7.2 PROVIDER ROUTER : $decision" -ForegroundColor $color
Write-Host ' ZERO SYSTEM MUTATION'
Write-Host '============================================================' -ForegroundColor $color
