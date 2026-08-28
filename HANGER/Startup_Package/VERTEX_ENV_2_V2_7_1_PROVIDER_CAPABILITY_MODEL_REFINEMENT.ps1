#requires -Version 7.0
<#
VERTEX ENV-2 V2.7.1 — PROVIDER CAPABILITY MODEL REFINEMENT
ZERO SYSTEM MUTATION

PURPOSE
  Refine provider capability semantics for Vertex Transaction Core.

Problem addressed:
  "Execute = False" is ambiguous.
  It may mean:
    - executor not implemented
    - executor implemented but not proven
    - executor proven but current session lacks privilege
    - operation blocked by policy
    - operation high-risk and intentionally disabled

New capability model:
  implemented
  proven
  available_now
  blocked_by
  risk_class
  rollback_ready
  observe_ready
  snapshot_ready
  verify_ready

ZERO SYSTEM MUTATION.
#>

[CmdletBinding()]
param(
    [ValidateSet('Audit')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$CoreRoot   = Join-Path $ReportRoot '_transaction_core'

if (-not (Test-Path -LiteralPath $CoreRoot)) {
    New-Item -ItemType Directory -Path $CoreRoot -Force | Out-Null
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

function Test-CommandAvailable {
    param([Parameter(Mandatory)][string]$Name)
    try {
        return $null -ne (Get-Command $Name -ErrorAction Stop)
    }
    catch {
        return $false
    }
}

function New-RefinedProviderCapability {
    param(
        [string]$ProviderName,
        [string]$ResourceType,
        [bool]$ObserveReady,
        [bool]$SnapshotReady,
        [bool]$VerifyReady,
        [bool]$ExecutorImplemented,
        [bool]$ExecutorProven,
        [bool]$AvailableNow,
        [string[]]$BlockedBy,
        [ValidateSet('LOW','MEDIUM','HIGH','CRITICAL')]
        [string]$RiskClass,
        [bool]$RollbackReady,
        [string]$LifecycleState,
        [string[]]$Notes
    )

    return [pscustomobject][ordered]@{
        provider_name          = $ProviderName
        resource_type          = $ResourceType

        observe_ready          = $ObserveReady
        snapshot_ready         = $SnapshotReady
        verify_ready           = $VerifyReady

        executor_implemented   = $ExecutorImplemented
        executor_proven        = $ExecutorProven
        available_now          = $AvailableNow
        blocked_by             = @($BlockedBy)

        rollback_ready         = $RollbackReady
        risk_class             = $RiskClass
        lifecycle_state        = $LifecycleState

        notes                  = @($Notes)
    }
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.7.1 — PROVIDER CAPABILITY MODEL' -ForegroundColor Magenta
Write-Host ' IMPLEMENTED / PROVEN / AVAILABLE_NOW / BLOCKED_BY / RISK' -ForegroundColor Magenta
Write-Host ' ZERO SYSTEM MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$isAdmin = Test-VertexAdministrator

Write-Host ''
Write-Host '[1/3] SESSION CAPABILITY' -ForegroundColor Cyan
Write-Host "  Administrator : $isAdmin"

# ------------------------------------------------------------
# Provider capability construction
# ------------------------------------------------------------
$providers = [System.Collections.Generic.List[object]]::new()

# Firewall
$fwObserve = Test-CommandAvailable 'Get-NetFirewallRule'
$fwRemove  = Test-CommandAvailable 'Remove-NetFirewallRule'
$fwCreate  = Test-CommandAvailable 'New-NetFirewallRule'
$fwImplemented = ($fwObserve -and $fwRemove -and $fwCreate)
$fwProven = $true
$fwBlocked = @()
if (-not $fwObserve) { $fwBlocked += 'NETSECURITY_UNAVAILABLE' }
if (-not $isAdmin)   { $fwBlocked += 'ADMIN_PRIVILEGE_REQUIRED' }
$fwAvailableNow = ($fwImplemented -and $isAdmin)

$providers.Add((New-RefinedProviderCapability `
    -ProviderName 'VertexFirewallProvider' `
    -ResourceType 'WINDOWS_FIREWALL_RULE' `
    -ObserveReady $fwObserve `
    -SnapshotReady $fwObserve `
    -VerifyReady $fwObserve `
    -ExecutorImplemented $fwImplemented `
    -ExecutorProven $fwProven `
    -AvailableNow $fwAvailableNow `
    -BlockedBy $fwBlocked `
    -RiskClass 'MEDIUM' `
    -RollbackReady ($fwCreate -and $fwObserve) `
    -LifecycleState 'PROVEN_TRANSACTION_PROVIDER' `
    -Notes @(
        'Commit-green transaction proven in V2.6.1.',
        'Post-commit verification + ledger proven in V2.6.2.',
        'Availability depends on current session privilege.'
    )
))

# Registry
$regObserve = $true
try {
    $null = Get-Item 'HKCU:\Software' -ErrorAction Stop
}
catch {
    $regObserve = $false
}
$regImplemented = $false
$regProven = $true
$regBlocked = @('UNIFIED_EXECUTOR_NOT_IMPLEMENTED')
if (-not $isAdmin) { $regBlocked += 'ADMIN_PRIVILEGE_MAY_BE_REQUIRED_FOR_MACHINE_SCOPE' }

$providers.Add((New-RefinedProviderCapability `
    -ProviderName 'VertexRegistryProvider' `
    -ResourceType 'WINDOWS_REGISTRY' `
    -ObserveReady $regObserve `
    -SnapshotReady $regObserve `
    -VerifyReady $regObserve `
    -ExecutorImplemented $regImplemented `
    -ExecutorProven $regProven `
    -AvailableNow $false `
    -BlockedBy $regBlocked `
    -RiskClass 'HIGH' `
    -RollbackReady $true `
    -LifecycleState 'PROVEN_FOUNDATION_AWAITING_VTC_EXECUTOR' `
    -Notes @(
        'Positive ownership + safe rollback proven previously.',
        'Machine scope requires stricter privilege boundary.',
        'Third-party drift must deny automatic restoration.'
    )
))

# Service
$svcObserve = (Test-CommandAvailable 'Get-Service') -and (Test-CommandAvailable 'Get-CimInstance')
$svcImplemented = $false
$svcProven = $true
$svcBlocked = @('UNIFIED_EXECUTOR_NOT_IMPLEMENTED')
if (-not $isAdmin) { $svcBlocked += 'ADMIN_PRIVILEGE_REQUIRED_FOR_MUTATION' }

$providers.Add((New-RefinedProviderCapability `
    -ProviderName 'VertexServiceProvider' `
    -ResourceType 'WINDOWS_SERVICE' `
    -ObserveReady $svcObserve `
    -SnapshotReady $svcObserve `
    -VerifyReady $svcObserve `
    -ExecutorImplemented $svcImplemented `
    -ExecutorProven $svcProven `
    -AvailableNow $false `
    -BlockedBy $svcBlocked `
    -RiskClass 'HIGH' `
    -RollbackReady $true `
    -LifecycleState 'PROVEN_FOUNDATION_AWAITING_VTC_EXECUTOR' `
    -Notes @(
        'Create/delete ownership case proven.',
        'Service config fingerprint must include path/start mode/account/state.'
    )
))

# Environment
$envObserve = $true
try {
    $null = [Environment]::GetEnvironmentVariables('User')
    $null = [Environment]::GetEnvironmentVariables('Machine')
}
catch {
    $envObserve = $false
}

$providers.Add((New-RefinedProviderCapability `
    -ProviderName 'VertexEnvironmentProvider' `
    -ResourceType 'WINDOWS_ENVIRONMENT' `
    -ObserveReady $envObserve `
    -SnapshotReady $envObserve `
    -VerifyReady $envObserve `
    -ExecutorImplemented $false `
    -ExecutorProven $false `
    -AvailableNow $false `
    -BlockedBy @('EXECUTOR_NOT_IMPLEMENTED') `
    -RiskClass 'HIGH' `
    -RollbackReady $true `
    -LifecycleState 'FOUNDATION_ONLY' `
    -Notes @(
        'PATH must be treated as an ordered collection.',
        'User and Machine scope must remain distinct.',
        'Rollback requires exact pre-image preservation.'
    )
))

# Scheduled Tasks
$taskObserve = Test-CommandAvailable 'Get-ScheduledTask'
$taskSnapshot = $taskObserve -and (Test-CommandAvailable 'Export-ScheduledTask')

$providers.Add((New-RefinedProviderCapability `
    -ProviderName 'VertexScheduledTaskProvider' `
    -ResourceType 'WINDOWS_SCHEDULED_TASK' `
    -ObserveReady $taskObserve `
    -SnapshotReady $taskSnapshot `
    -VerifyReady $taskObserve `
    -ExecutorImplemented $false `
    -ExecutorProven $false `
    -AvailableNow $false `
    -BlockedBy @('EXECUTOR_NOT_IMPLEMENTED') `
    -RiskClass 'HIGH' `
    -RollbackReady $taskSnapshot `
    -LifecycleState 'FOUNDATION_ONLY' `
    -Notes @(
        'Task identity = TaskPath + TaskName.',
        'Rollback candidate is exported XML.',
        'Principal/run-level/triggers/actions must be fingerprinted.'
    )
))

# Certificates
$certObserve = (Test-Path 'Cert:\CurrentUser\My') -or (Test-Path 'Cert:\LocalMachine\My')

$providers.Add((New-RefinedProviderCapability `
    -ProviderName 'VertexCertificateProvider' `
    -ResourceType 'WINDOWS_CERTIFICATE' `
    -ObserveReady $certObserve `
    -SnapshotReady $certObserve `
    -VerifyReady $certObserve `
    -ExecutorImplemented $false `
    -ExecutorProven $false `
    -AvailableNow $false `
    -BlockedBy @('EXECUTOR_NOT_IMPLEMENTED','ROLLBACK_POLICY_NOT_PROVEN','HIGH_RISK_POLICY_GATE') `
    -RiskClass 'CRITICAL' `
    -RollbackReady $false `
    -LifecycleState 'HIGH_RISK_FOUNDATION_ONLY' `
    -Notes @(
        'Private-key exportability cannot be assumed.',
        'Thumbprint + Store location form minimum identity.',
        'Certificate removal must never rely on Subject alone.'
    )
))

Write-Host ''
Write-Host '[2/3] REFINED PROVIDER MATRIX' -ForegroundColor Cyan

foreach ($p in $providers) {
    $color = if ($p.available_now) {
        'Green'
    }
    elseif ($p.executor_proven) {
        'Cyan'
    }
    elseif ($p.risk_class -eq 'CRITICAL') {
        'Red'
    }
    else {
        'Yellow'
    }

    Write-Host "[$($p.lifecycle_state)] $($p.provider_name)" -ForegroundColor $color
    Write-Host "  Implemented   : $($p.executor_implemented)"
    Write-Host "  Proven        : $($p.executor_proven)"
    Write-Host "  Available Now : $($p.available_now)"
    Write-Host "  Blocked By    : $(if(@($p.blocked_by).Count){$p.blocked_by -join ', '}else{'NONE'})"
    Write-Host "  Risk          : $($p.risk_class)"
    Write-Host "  Rollback      : $($p.rollback_ready)"
}

# ------------------------------------------------------------
# Common capability semantics
# ------------------------------------------------------------
$semantics = [ordered]@{
    schema = 'vertex.transaction.capability-model.v1'
    meanings = [ordered]@{
        executor_implemented = 'Provider contains an execution implementation in the common VTC model.'
        executor_proven      = 'Provider mutation + verification behavior has been proven in prior execution.'
        available_now        = 'Provider can execute safely in the current session/environment right now.'
        blocked_by           = 'Current reasons preventing execution.'
        risk_class           = 'Safety/risk classification independent of implementation status.'
        rollback_ready       = 'A tested or structurally sufficient rollback path exists.'
    }
    rule = 'Never infer implementation status from current session availability.'
}

Write-Host ''
Write-Host '[3/3] CAPABILITY MANIFEST' -ForegroundColor Cyan

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $CoreRoot "VERTEX_PROVIDER_CAPABILITY_MODEL.$stamp.json"
$txt  = Join-Path $CoreRoot "VERTEX_PROVIDER_CAPABILITY_MODEL.$stamp.txt"

$manifest = [ordered]@{
    schema = 'vertex.transaction.provider-capability-manifest.v1'
    version = '2.7.1'
    generated_at = (Get-Date).ToString('o')
    mode = $Mode
    administrator = $isAdmin
    semantics = $semantics
    providers = @($providers)

    summary = [ordered]@{
        providers_total = $providers.Count
        executor_implemented = @($providers | Where-Object executor_implemented).Count
        executor_proven = @($providers | Where-Object executor_proven).Count
        available_now = @($providers | Where-Object available_now).Count
        rollback_ready = @($providers | Where-Object rollback_ready).Count
        critical_risk = @($providers | Where-Object risk_class -eq 'CRITICAL').Count
    }

    safety = [ordered]@{
        system_mutation = 'NONE'
        report_write_only = $true
    }
}

$manifest | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX PROVIDER CAPABILITY MODEL V2.7.1',
    '============================================================',
    " Administrator          : $isAdmin",
    " Providers              : $($manifest.summary.providers_total)",
    " Executor Implemented   : $($manifest.summary.executor_implemented)",
    " Executor Proven        : $($manifest.summary.executor_proven)",
    " Available Now          : $($manifest.summary.available_now)",
    " Rollback Ready         : $($manifest.summary.rollback_ready)",
    " Critical Risk          : $($manifest.summary.critical_risk)",
    '',
    ' SYSTEM MUTATION        : NONE',
    ' REPORT WRITE           : ALLOWED',
    '',
    " JSON                   : $json",
    " TXT                    : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' V2.7.1 PROVIDER CAPABILITY MODEL : GREEN' -ForegroundColor Green
Write-Host " Providers     : $($manifest.summary.providers_total)"
Write-Host " Implemented   : $($manifest.summary.executor_implemented)"
Write-Host " Proven        : $($manifest.summary.executor_proven)"
Write-Host " Available Now : $($manifest.summary.available_now)"
Write-Host " JSON          : $json"
Write-Host " TXT           : $txt"
Write-Host ' ZERO SYSTEM MUTATION' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
