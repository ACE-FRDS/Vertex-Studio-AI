#requires -Version 7.0
<#
VERTEX ENV-2 V2.7 — VERTEX TRANSACTION CORE FOUNDATION
COMMON TRANSACTION PROTOCOL / PROVIDER CONTRACT / ZERO SYSTEM MUTATION

PURPOSE
  Extract the proven firewall transaction pattern into a common transaction core.

COMMON FLOW
  OBSERVE
    -> EVIDENCE
    -> OWNERSHIP
    -> PLAN
    -> SNAPSHOT
    -> HUMAN GATE
    -> EXECUTE
    -> VERIFY
    -> COMMIT / ROLLBACK
    -> LEDGER

THIS FOUNDATION DOES NOT MUTATE:
  - Firewall
  - Registry
  - Services
  - PATH / Environment
  - Scheduled Tasks
  - Certificates

It audits provider capability and emits a common transaction-core manifest.
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

function New-ProviderCapability {
    param(
        [string]$Name,
        [string]$ResourceType,
        [bool]$Observe,
        [bool]$Snapshot,
        [bool]$ExecuteAvailable,
        [bool]$Verify,
        [bool]$RollbackDesigned,
        [string]$ExecutionState,
        [string[]]$Notes
    )

    return [pscustomobject][ordered]@{
        provider_name      = $Name
        resource_type      = $ResourceType
        observe            = $Observe
        snapshot           = $Snapshot
        execute_available  = $ExecuteAvailable
        verify             = $Verify
        rollback_designed  = $RollbackDesigned
        execution_state    = $ExecutionState
        notes              = @($Notes)
    }
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.7 — VERTEX TRANSACTION CORE FOUNDATION' -ForegroundColor Magenta
Write-Host ' COMMON PROTOCOL / PROVIDER CONTRACT / STATE MACHINE' -ForegroundColor Magenta
Write-Host ' ZERO SYSTEM MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$isAdmin = Test-VertexAdministrator

# ------------------------------------------------------------
# PROVIDER CAPABILITY AUDIT
# ------------------------------------------------------------
Write-Host ''
Write-Host '[1/4] PROVIDER CAPABILITY AUDIT' -ForegroundColor Cyan

$providers = [System.Collections.Generic.List[object]]::new()

# Firewall — proven transaction implementation exists.
$firewallObserve = Test-CommandAvailable 'Get-NetFirewallRule'
$firewallExecute = Test-CommandAvailable 'Remove-NetFirewallRule'
$firewallCreate  = Test-CommandAvailable 'New-NetFirewallRule'

$providers.Add((New-ProviderCapability `
    -Name 'VertexFirewallProvider' `
    -ResourceType 'WINDOWS_FIREWALL_RULE' `
    -Observe $firewallObserve `
    -Snapshot $firewallObserve `
    -ExecuteAvailable ($firewallExecute -and $isAdmin) `
    -Verify $firewallObserve `
    -RollbackDesigned ($firewallCreate -and $firewallObserve) `
    -ExecutionState 'PROVEN_COMMIT_GREEN' `
    -Notes @(
        'V2.6.1 transaction execution proven.',
        'V2.6.2 post-commit ledger proven.',
        'Exact fingerprint matching required.'
    )
))

# Registry — ownership/rollback prototype exists from V1.6-V1.9.
$registryObserve = $true
try {
    $null = Get-Item 'HKCU:\Software' -ErrorAction Stop
}
catch {
    $registryObserve = $false
}

$providers.Add((New-ProviderCapability `
    -Name 'VertexRegistryProvider' `
    -ResourceType 'WINDOWS_REGISTRY' `
    -Observe $registryObserve `
    -Snapshot $registryObserve `
    -ExecuteAvailable $false `
    -Verify $registryObserve `
    -RollbackDesigned $true `
    -ExecutionState 'FOUNDATION_PROVEN_EXECUTOR_NOT_UNIFIED' `
    -Notes @(
        'Ownership and safe rollback were proven before common transaction core.',
        'Unified VTC executor not yet implemented.',
        'Third-party drift must deny automatic restore.'
    )
))

# Service — ownership/rollback prototype exists from V2.0-V2.3.
$serviceObserve = Test-CommandAvailable 'Get-Service'
$serviceCim     = Test-CommandAvailable 'Get-CimInstance'

$providers.Add((New-ProviderCapability `
    -Name 'VertexServiceProvider' `
    -ResourceType 'WINDOWS_SERVICE' `
    -Observe ($serviceObserve -and $serviceCim) `
    -Snapshot ($serviceObserve -and $serviceCim) `
    -ExecuteAvailable $false `
    -Verify ($serviceObserve -and $serviceCim) `
    -RollbackDesigned $true `
    -ExecutionState 'FOUNDATION_PROVEN_EXECUTOR_NOT_UNIFIED' `
    -Notes @(
        'Create/delete ownership case already proven.',
        'Unified VTC executor not yet implemented.',
        'Service path/config/state fingerprint required.'
    )
))

# PATH / Environment
$envObserve = $true
try {
    $null = [Environment]::GetEnvironmentVariables('Machine')
    $null = [Environment]::GetEnvironmentVariables('User')
}
catch {
    $envObserve = $false
}

$providers.Add((New-ProviderCapability `
    -Name 'VertexEnvironmentProvider' `
    -ResourceType 'WINDOWS_ENVIRONMENT' `
    -Observe $envObserve `
    -Snapshot $envObserve `
    -ExecuteAvailable $false `
    -Verify $envObserve `
    -RollbackDesigned $true `
    -ExecutionState 'NOT_IMPLEMENTED' `
    -Notes @(
        'Requires User + Machine scope separation.',
        'PATH must be treated as ordered list, not opaque string.',
        'Rollback requires exact pre-image preservation.'
    )
))

# Scheduled Tasks
$taskObserve = Test-CommandAvailable 'Get-ScheduledTask'
$taskExport  = Test-CommandAvailable 'Export-ScheduledTask'

$providers.Add((New-ProviderCapability `
    -Name 'VertexScheduledTaskProvider' `
    -ResourceType 'WINDOWS_SCHEDULED_TASK' `
    -Observe $taskObserve `
    -Snapshot ($taskObserve -and $taskExport) `
    -ExecuteAvailable $false `
    -Verify $taskObserve `
    -RollbackDesigned ($taskObserve -and $taskExport) `
    -ExecutionState 'NOT_IMPLEMENTED' `
    -Notes @(
        'XML export can provide rollback snapshot.',
        'Task path + task name form compound identity.',
        'Principal/run-level/triggers/actions must be fingerprinted.'
    )
))

# Certificates
$certObserve = Test-Path 'Cert:\CurrentUser\My'
$certMachine = Test-Path 'Cert:\LocalMachine\My'

$providers.Add((New-ProviderCapability `
    -Name 'VertexCertificateProvider' `
    -ResourceType 'WINDOWS_CERTIFICATE' `
    -Observe ($certObserve -or $certMachine) `
    -Snapshot ($certObserve -or $certMachine) `
    -ExecuteAvailable $false `
    -Verify ($certObserve -or $certMachine) `
    -RollbackDesigned $false `
    -ExecutionState 'NOT_IMPLEMENTED_HIGH_RISK' `
    -Notes @(
        'Private-key exportability cannot be assumed.',
        'Certificate rollback semantics require stricter policy.',
        'Never remove by subject name alone; thumbprint/store identity required.'
    )
))

foreach ($p in $providers) {
    $color = switch ($p.execution_state) {
        'PROVEN_COMMIT_GREEN' { 'Green' }
        'FOUNDATION_PROVEN_EXECUTOR_NOT_UNIFIED' { 'Cyan' }
        'NOT_IMPLEMENTED' { 'Yellow' }
        default { 'DarkYellow' }
    }

    Write-Host "[$($p.execution_state)] $($p.provider_name)" -ForegroundColor $color
    Write-Host "  Resource : $($p.resource_type)"
    Write-Host "  Observe  : $($p.observe)"
    Write-Host "  Snapshot : $($p.snapshot)"
    Write-Host "  Execute  : $($p.execute_available)"
    Write-Host "  Verify   : $($p.verify)"
    Write-Host "  Rollback : $($p.rollback_designed)"
}

# ------------------------------------------------------------
# COMMON PROVIDER CONTRACT
# ------------------------------------------------------------
Write-Host ''
Write-Host '[2/4] COMMON PROVIDER CONTRACT' -ForegroundColor Cyan

$providerContract = [ordered]@{
    schema = 'vertex.transaction.provider-contract.v1'
    required_operations = @(
        'Observe',
        'ResolveIdentity',
        'CaptureEvidence',
        'DetermineOwnership',
        'BuildPlan',
        'Snapshot',
        'ValidatePreconditions',
        'Execute',
        'Verify',
        'Rollback',
        'PostVerify',
        'WriteLedger'
    )
    invariants = @(
        'No mutation before snapshot exists.',
        'No mutation before human gate when policy requires it.',
        'Exact identity must be resolved before execute.',
        'Live state must be revalidated immediately before mutation.',
        'Every mutation must have verification.',
        'Any failed mutation path must stop subsequent operations.',
        'Rollback applies only to resources already mutated.',
        'Commit occurs only when all verification checks are green.',
        'Ledger entry is written only from verified transaction evidence.',
        'Third-party drift invalidates automatic rollback assumptions.'
    )
}

Write-Host "  Required Operations : $($providerContract.required_operations.Count)"
Write-Host "  Core Invariants     : $($providerContract.invariants.Count)"

# ------------------------------------------------------------
# TRANSACTION STATE MACHINE
# ------------------------------------------------------------
Write-Host ''
Write-Host '[3/4] TRANSACTION STATE MACHINE' -ForegroundColor Cyan

$stateMachine = [ordered]@{
    schema = 'vertex.transaction.state-machine.v1'
    states = @(
        'DISCOVERED',
        'EVIDENCE_COLLECTED',
        'OWNERSHIP_RESOLVED',
        'PLANNED',
        'SNAPSHOT_READY',
        'HUMAN_GATE_PENDING',
        'PRE_FLIGHT_GREEN',
        'EXECUTING',
        'VERIFYING',
        'COMMIT_GREEN',
        'ROLLBACK_REQUIRED',
        'ROLLING_BACK',
        'ROLLBACK_GREEN',
        'ROLLBACK_RED',
        'POST_COMMIT_GREEN',
        'POST_COMMIT_RED',
        'COMMITTED_VERIFIED',
        'REVIEW_REQUIRED'
    )
    terminal_states = @(
        'COMMITTED_VERIFIED',
        'ROLLBACK_GREEN',
        'ROLLBACK_RED',
        'REVIEW_REQUIRED'
    )
    forbidden_transitions = @(
        'DISCOVERED -> EXECUTING',
        'PLANNED -> EXECUTING without SNAPSHOT_READY',
        'SNAPSHOT_READY -> EXECUTING when HUMAN_GATE_PENDING',
        'EXECUTING -> COMMIT_GREEN without VERIFYING',
        'ROLLING_BACK -> COMMIT_GREEN'
    )
}

Write-Host "  States               : $($stateMachine.states.Count)"
Write-Host "  Terminal States      : $($stateMachine.terminal_states.Count)"
Write-Host "  Forbidden Transitions: $($stateMachine.forbidden_transitions.Count)"

# ------------------------------------------------------------
# CORE MANIFEST
# ------------------------------------------------------------
Write-Host ''
Write-Host '[4/4] CORE MANIFEST' -ForegroundColor Cyan

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json  = Join-Path $CoreRoot "VERTEX_TRANSACTION_CORE_FOUNDATION.$stamp.json"
$txt   = Join-Path $CoreRoot "VERTEX_TRANSACTION_CORE_FOUNDATION.$stamp.txt"

$manifest = [ordered]@{
    schema = 'vertex.transaction.core-foundation.v1'
    version = '2.7'
    generated_at = (Get-Date).ToString('o')
    mode = $Mode
    administrator = $isAdmin

    transaction_principle = 'Do not touch state until the return path exists.'

    common_flow = @(
        'OBSERVE',
        'EVIDENCE',
        'OWNERSHIP',
        'PLAN',
        'SNAPSHOT',
        'HUMAN_GATE',
        'EXECUTE',
        'VERIFY',
        'COMMIT_OR_ROLLBACK',
        'LEDGER'
    )

    provider_contract = $providerContract
    state_machine = $stateMachine
    providers = @($providers)

    safety = [ordered]@{
        firewall_mutation       = 'NONE'
        registry_mutation       = 'NONE'
        service_mutation        = 'NONE'
        environment_mutation    = 'NONE'
        scheduled_task_mutation = 'NONE'
        certificate_mutation    = 'NONE'
        report_write_only       = $true
    }
}

$manifest | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX TRANSACTION CORE FOUNDATION V2.7',
    '============================================================',
    " Administrator               : $isAdmin",
    " Providers                   : $($providers.Count)",
    " Common Operations           : $($providerContract.required_operations.Count)",
    " State Machine States        : $($stateMachine.states.Count)",
    '',
    ' PROVIDERS',
    " Firewall                    : $((@($providers | Where-Object resource_type -eq 'WINDOWS_FIREWALL_RULE'))[0].execution_state)",
    " Registry                    : $((@($providers | Where-Object resource_type -eq 'WINDOWS_REGISTRY'))[0].execution_state)",
    " Service                     : $((@($providers | Where-Object resource_type -eq 'WINDOWS_SERVICE'))[0].execution_state)",
    " PATH / Environment          : $((@($providers | Where-Object resource_type -eq 'WINDOWS_ENVIRONMENT'))[0].execution_state)",
    " Scheduled Tasks             : $((@($providers | Where-Object resource_type -eq 'WINDOWS_SCHEDULED_TASK'))[0].execution_state)",
    " Certificates                : $((@($providers | Where-Object resource_type -eq 'WINDOWS_CERTIFICATE'))[0].execution_state)",
    '',
    ' SYSTEM MUTATION             : NONE',
    ' REPORT WRITE                : ALLOWED',
    '',
    " JSON                        : $json",
    " TXT                         : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' V2.7 VERTEX TRANSACTION CORE FOUNDATION : GREEN' -ForegroundColor Green
Write-Host " Providers : $($providers.Count)"
Write-Host " JSON      : $json"
Write-Host " TXT       : $txt"
Write-Host ' ZERO SYSTEM MUTATION' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
