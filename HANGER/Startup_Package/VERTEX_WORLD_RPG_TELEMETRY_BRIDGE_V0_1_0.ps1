#requires -Version 7.0
<#
VERTEX WORLD — RPG TELEMETRY BRIDGE V0.1.0

Purpose:
  Convert real ARD/VXN experiment receipts into an RPG-facing telemetry/state layer.
  This does NOT invent gameplay results. It derives presentation state from execution evidence.

Safety:
  - Reads experiment receipts.
  - Writes only under VXN\runtime\rpg and VXN\observability\rpg.
  - No canonical mutation.
  - No VTC execution.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'G:\Vertex_Project\Vertex_Studio_AI',
    [string]$VxnRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VxnRoot)) {
    $VxnRoot = Join-Path $ProjectRoot 'VXN'
}

$rpgRoot = Join-Path $VxnRoot 'runtime\rpg'
$obsRoot = Join-Path $VxnRoot 'observability\rpg'
$profileRoot = Join-Path $rpgRoot 'profiles'
$battleRoot = Join-Path $rpgRoot 'battle_logs'
$stateRoot = Join-Path $rpgRoot 'state'

@($rpgRoot,$obsRoot,$profileRoot,$battleRoot,$stateRoot) | ForEach-Object {
    $null = New-Item -ItemType Directory -Force -Path $_
}

function Write-Json([string]$Path, $Object) {
    $Object | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonSafe([string]$Path) {
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-Prop($Object,[string]$Name,$Default=$null) {
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Get-LatestReceipt {
    $roots = @(
        (Join-Path $VxnRoot 'experiments\ard_parallel_width'),
        (Join-Path $VxnRoot 'experiments\ard_parallel')
    )

    $files = @()
    foreach ($root in $roots) {
        if (Test-Path $root) {
            $files += Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.json' |
                Where-Object { $_.Name -match 'RECEIPT' }
        }
    }

    return $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Get-RoleClass([string]$Role) {
    switch -Regex ($Role) {
        'Explorer'   { 'SCOUT'; break }
        'Planner'    { 'TACTICIAN'; break }
        'Critic'     { 'ANALYST'; break }
        'ScopeGuard' { 'GUARDIAN'; break }
        'Verifier'   { 'VERIFIER'; break }
        'Optimizer'  { 'ENGINEER'; break }
        default      { 'AGENT' }
    }
}

function Get-ModelTier([string]$Model) {
    if ($Model -match '(?i)(30|32)b') { return '30B' }
    if ($Model -match '(?i)(12|13|14)b') { return '12B' }
    if ($Model -match '(?i)(7|8|9)b') { return '8B' }
    if ($Model -match '(?i)(3|4)b') { return '3B4B' }
    return 'UNKNOWN'
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX WORLD — RPG TELEMETRY BRIDGE V0.1.0' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$receiptFile = Get-LatestReceipt
if ($null -eq $receiptFile) {
    throw 'No ARD experiment receipt found.'
}

$receipt = Read-JsonSafe $receiptFile.FullName
if ($null -eq $receipt) {
    throw "Could not parse receipt: $($receiptFile.FullName)"
}

Write-Host "Source Receipt : $($receiptFile.FullName)"

$runId = [string](Get-Prop $receipt 'run_id' $receiptFile.Directory.Name)
$status = [string](Get-Prop $receipt 'status' 'UNKNOWN')

$party = Get-Prop $receipt 'party' $null
$partyModel = [string](Get-Prop $party 'model' '')
$partyTier = Get-ModelTier $partyModel

$logicalPartySize = [int](Get-Prop $receipt 'logical_party_size' 0)
$stableWidth = [int](Get-Prop $receipt 'last_proven_stable_width' 0)
$probeWidth = [int](Get-Prop $receipt 'current_probe_width' 0)

if ($stableWidth -eq 0) {
    $stableWidth = [int](Get-Prop $receipt 'final_parallel_width' 0)
}
if ($probeWidth -eq 0) {
    $probeWidth = $stableWidth
}

$integrator = Get-Prop $receipt 'integrator' $null
$integratorModel = [string](Get-Prop $integrator 'model' '')
$integratorGreen = [bool](Get-Prop $integrator 'green' $false)
$integratorScore = [double](Get-Prop $integrator 'score' 0)

$escalation = Get-Prop $receipt 'escalation' $null
$escalationUsed = [bool](Get-Prop $escalation 'used' $false)
$finalModel = [string](Get-Prop $escalation 'final_model' $integratorModel)

$final = Get-Prop $receipt 'final' $null
$finalGreen = [bool](Get-Prop $final 'green' ($status -eq 'GREEN'))
$finalScore = [double](Get-Prop $final 'score' 0)

$roleResults = @()
if ($null -ne $party) {
    $roleResults = @(Get-Prop $party 'results' @())
}

$characters = @()
foreach ($r in $roleResults) {
    $role = [string](Get-Prop $r 'Role' (Get-Prop $r 'role' 'Agent'))
    $latency = [double](Get-Prop $r 'LatencyMs' (Get-Prop $r 'latency_ms' 0))
    $success = [bool](Get-Prop $r 'Success' (Get-Prop $r 'success' $true))

    $speed = if ($latency -le 0) { 50 } elseif ($latency -lt 7000) { 90 } elseif ($latency -lt 12000) { 75 } elseif ($latency -lt 20000) { 60 } else { 40 }
    $reliability = if ($success) { 85 } else { 25 }

    $characters += [ordered]@{
        character_id = "ARD-$role"
        display_name = $role
        class = Get-RoleClass $role
        model = $partyModel
        model_tier = $partyTier
        status = if ($success) { 'READY' } else { 'RECOVERY' }
        measured_stats = [ordered]@{
            speed_index = $speed
            reliability_index = $reliability
            latency_ms = $latency
        }
        note = 'Stats are telemetry-derived presentation values, not model parameter rankings.'
    }
}

$waveScheduler = Get-Prop $receipt 'wave_scheduler' $null
$waves = @(Get-Prop $waveScheduler 'receipts' @())

$events = @()
foreach ($w in $waves) {
    $width = [int](Get-Prop $w 'requested_width' 0)
    $http500 = [int](Get-Prop $w 'http500_count' 0)
    $successCount = [int](Get-Prop $w 'success_count' 0)
    $failureCount = [int](Get-Prop $w 'failure_count' 0)

    $events += [ordered]@{
        event = 'PARTY_WAVE'
        wave = Get-Prop $w 'wave' 0
        attempt = Get-Prop $w 'attempt' 0
        physical_width = $width
        success_count = $successCount
        failure_count = $failureCount
        http_500_count = $http500
        rpg_message = if ($http500 -gt 0) {
            "Runtime overload detected at width $width."
        } else {
            "Formation stable at width $width."
        }
    }
}

if ($integratorGreen) {
    $events += [ordered]@{
        event='INTEGRATION_GREEN'
        model=$integratorModel
        score=$integratorScore
        rpg_message='Party knowledge integrated successfully.'
    }
} else {
    $events += [ordered]@{
        event='INTEGRATION_NOT_GREEN'
        model=$integratorModel
        score=$integratorScore
        rpg_message='Party requires senior support.'
    }
}

if ($escalationUsed) {
    $events += [ordered]@{
        event='SUPPORT_SUMMON'
        model=$finalModel
        model_tier=(Get-ModelTier $finalModel)
        rpg_message='Senior support entered the mission.'
    }
}

$battleLog = [ordered]@{
    schema='vertex.world.rpg.execution-log.v1'
    run_id=$runId
    source_receipt=$receiptFile.FullName
    mission_result=if ($finalGreen) { 'MISSION_CLEAR' } else { 'MISSION_HOLD' }
    final_score=$finalScore
    party=[ordered]@{
        logical_size=$logicalPartySize
        model=$partyModel
        tier=$partyTier
        stable_physical_width=$stableWidth
        next_probe_width=$probeWidth
        characters=$characters
    }
    command=[ordered]@{
        integrator=$integratorModel
        integrator_green=$integratorGreen
        escalation_used=$escalationUsed
        final_model=$finalModel
    }
    events=$events
    safety=[ordered]@{
        canonical_mutation='NONE'
        vtc_execution='NONE'
    }
}

$battlePath = Join-Path $battleRoot "$runId.RPG_BATTLE_LOG.json"
Write-Json $battlePath $battleLog

# Persistent runtime experience profile.
$profilePath = Join-Path $profileRoot 'ARD_RUNTIME_EXPERIENCE.json'
$profile = Read-JsonSafe $profilePath

$history = @()
if ($null -ne $profile) {
    $history = @(Get-Prop $profile 'history' @())
}

$history += [ordered]@{
    run_id=$runId
    timestamp=(Get-Date).ToString('o')
    party_model=$partyModel
    party_size=$logicalPartySize
    stable_width=$stableWidth
    probe_width=$probeWidth
    integrator_model=$integratorModel
    escalation_used=$escalationUsed
    final_green=$finalGreen
    final_score=$finalScore
}

if ($history.Count -gt 100) {
    $history = @($history | Select-Object -Last 100)
}

$successfulRuns = @($history | Where-Object { $_.final_green -eq $true })
$stableSamples = @($successfulRuns | Where-Object { $_.stable_width -gt 0 })

$recommendedWidth = $stableWidth
if ($stableSamples.Count -gt 0) {
    # Conservative: median of proven successful widths.
    $sorted = @($stableSamples.stable_width | Sort-Object)
    $recommendedWidth = [int]$sorted[[math]::Floor(($sorted.Count - 1) / 2)]
}

$experience = [ordered]@{
    schema='vertex.world.rpg.runtime-experience.v1'
    updated_at=(Get-Date).ToString('o')
    runtime_identity=[ordered]@{
        party_model=$partyModel
        logical_party_size=$logicalPartySize
    }
    progression=[ordered]@{
        missions_recorded=$history.Count
        successful_missions=$successfulRuns.Count
        recommended_parallel_width=$recommendedWidth
        current_probe_width=$probeWidth
    }
    history=$history
}

Write-Json $profilePath $experience

$currentState = [ordered]@{
    schema='vertex.world.rpg.current-state.v1'
    updated_at=(Get-Date).ToString('o')
    mission=$runId
    mission_state=$battleLog.mission_result
    party_size=$logicalPartySize
    stable_width=$stableWidth
    probe_width=$probeWidth
    party_model=$partyModel
    integrator_model=$integratorModel
    escalation_used=$escalationUsed
    final_model=$finalModel
    final_score=$finalScore
}

$statePath = Join-Path $stateRoot 'CURRENT_RPG_STATE.json'
Write-Json $statePath $currentState

$observerPath = Join-Path $obsRoot 'RPG_TELEMETRY_BRIDGE_RECEIPT.json'
Write-Json $observerPath ([ordered]@{
    schema='vertex.world.rpg.telemetry-bridge-receipt.v1'
    completed_at=(Get-Date).ToString('o')
    source=$receiptFile.FullName
    outputs=@($battlePath,$profilePath,$statePath)
    canonical_mutation='NONE'
    vtc_execution='NONE'
})

Write-Host ''
Write-Host '[RPG PARTY]' -ForegroundColor Cyan
Write-Host "  Party Model   : $partyModel"
Write-Host "  Logical Size  : $logicalPartySize"
Write-Host "  Stable Width  : $stableWidth"
Write-Host "  Probe Width   : $probeWidth"

Write-Host ''
Write-Host '[MISSION]' -ForegroundColor Cyan
Write-Host "  Integrator    : $integratorModel"
Write-Host "  Escalation    : $escalationUsed"
Write-Host "  Final Model   : $finalModel"
Write-Host "  Result        : $($battleLog.mission_result)"
Write-Host "  Score         : $finalScore"

Write-Host ''
Write-Host '[EXPERIENCE]' -ForegroundColor Cyan
Write-Host "  Missions      : $($history.Count)"
Write-Host "  Clears        : $($successfulRuns.Count)"
Write-Host "  Recommended W : $recommendedWidth"

Write-Host ''
Write-Host "Battle Log      : $battlePath"
Write-Host "Experience      : $profilePath"
Write-Host "Current State   : $statePath"
Write-Host ''
Write-Host 'RPG DISPLAY DATA IS DERIVED FROM REAL ARD/VXN TELEMETRY.'
Write-Host 'CANONICAL MUTATION : NONE'
Write-Host 'VTC EXECUTION      : NONE'
Write-Host ''
Write-Host 'VERTEX WORLD ONLINE.'
Write-Host '轟。' -ForegroundColor Green
