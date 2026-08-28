#requires -Version 7.0
<#
VERTEX WORLD — RPG PROGRESSION ENGINE V0.1.0

PURPOSE
  Convert real ARD/VXN telemetry history into persistent RPG progression.

PRINCIPLES
  - No fake XP.
  - No arbitrary "power level" detached from evidence.
  - Progress derives from actual missions, role success, runtime stability,
    integration success, escalation behavior, and measured latency.
  - Parameter count alone does not define strength.

SAFETY
  - Reads VXN runtime RPG telemetry.
  - Writes only under VXN\runtime\rpg.
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
$battleRoot = Join-Path $rpgRoot 'battle_logs'
$profileRoot = Join-Path $rpgRoot 'profiles'
$progressionRoot = Join-Path $rpgRoot 'progression'
$partyRoot = Join-Path $rpgRoot 'parties'
$characterRoot = Join-Path $rpgRoot 'characters'
$receiptRoot = Join-Path $rpgRoot 'receipts'

@(
    $progressionRoot,
    $partyRoot,
    $characterRoot,
    $receiptRoot
) | ForEach-Object {
    $null = New-Item -ItemType Directory -Path $_ -Force
}

function Banner([string]$Text) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Magenta
    Write-Host " $Text" -ForegroundColor Magenta
    Write-Host '============================================================' -ForegroundColor Magenta
}

function Write-Json([string]$Path, $Object) {
    $parent = Split-Path -Parent $Path
    if ($parent) { $null = New-Item -ItemType Directory -Path $parent -Force }
    $Object | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-Prop {
    param($Object,[string]$Name,$Default=$null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Get-LevelFromXp([double]$Xp) {
    # Smooth progression from observed evidence.
    # Level is a presentation index, but XP itself is evidence-derived.
    return [int][math]::Floor([math]::Sqrt([math]::Max(0,$Xp) / 100.0)) + 1
}

function Get-Rank([int]$Level,[double]$SuccessRate) {
    if ($Level -ge 20 -and $SuccessRate -ge 0.95) { return 'S' }
    if ($Level -ge 15 -and $SuccessRate -ge 0.90) { return 'A' }
    if ($Level -ge 10 -and $SuccessRate -ge 0.85) { return 'B' }
    if ($Level -ge 6  -and $SuccessRate -ge 0.75) { return 'C' }
    if ($Level -ge 3  -and $SuccessRate -ge 0.60) { return 'D' }
    return 'E'
}

function Get-LatencyEfficiency([double]$LatencyMs) {
    if ($LatencyMs -le 0) { return 0.5 }
    if ($LatencyMs -lt 5000) { return 1.0 }
    if ($LatencyMs -lt 8000) { return 0.9 }
    if ($LatencyMs -lt 12000) { return 0.8 }
    if ($LatencyMs -lt 20000) { return 0.65 }
    if ($LatencyMs -lt 30000) { return 0.50 }
    return 0.35
}

function Ensure-CharacterProfile {
    param(
        [hashtable]$Profiles,
        [string]$CharacterId,
        [string]$DisplayName,
        [string]$Class,
        [string]$Model,
        [string]$ModelTier
    )

    if (-not $Profiles.ContainsKey($CharacterId)) {
        $Profiles[$CharacterId] = [ordered]@{
            character_id=$CharacterId
            display_name=$DisplayName
            class=$Class
            model=$Model
            model_tier=$ModelTier

            evidence=[ordered]@{
                missions=0
                successes=0
                failures=0
                total_latency_ms=0.0
                measured_samples=0
            }

            progression=[ordered]@{
                xp=0.0
                level=1
                rank='E'
            }

            affinities=[ordered]@{
                explorer=0
                planner=0
                critic=0
                scope_guard=0
                verifier=0
                optimizer=0
                integration=0
                review=0
            }

            equipment_affinity=[ordered]@{
                lock_scope=0
                vcc_vsp=0
                candidate_vtc=0
                impact_association=0
            }
        }
    }
}

function Add-RoleAffinity {
    param($Profile,[string]$Role,[int]$Value)

    switch -Regex ($Role) {
        '^Explorer$'   { $Profile.affinities.explorer += $Value }
        '^Planner$'    { $Profile.affinities.planner += $Value }
        '^Critic$'     { $Profile.affinities.critic += $Value }
        '^ScopeGuard$' { $Profile.affinities.scope_guard += $Value }
        '^Verifier$'   { $Profile.affinities.verifier += $Value }
        '^Optimizer$'  { $Profile.affinities.optimizer += $Value }
    }
}

function Get-Class([string]$Role) {
    switch -Regex ($Role) {
        'Explorer'   { return 'SCOUT' }
        'Planner'    { return 'TACTICIAN' }
        'Critic'     { return 'ANALYST' }
        'ScopeGuard' { return 'GUARDIAN' }
        'Verifier'   { return 'VERIFIER' }
        'Optimizer'  { return 'ENGINEER' }
        default      { return 'AGENT' }
    }
}

function Get-ModelTier([string]$Model) {
    if ($Model -match '(?i)(30|32|34)b') { return '30B' }
    if ($Model -match '(?i)(12|13|14)b') { return '12B' }
    if ($Model -match '(?i)(7|8|9)b') { return '8B' }
    if ($Model -match '(?i)(3|4)b') { return '3B4B' }
    return 'UNKNOWN'
}

Banner 'VERTEX WORLD — RPG PROGRESSION ENGINE V0.1.0'

if (-not (Test-Path -LiteralPath $battleRoot)) {
    throw "RPG battle log directory not found: $battleRoot"
}

$battleFiles = @(
    Get-ChildItem -LiteralPath $battleRoot -Filter '*.RPG_BATTLE_LOG.json' -File |
    Sort-Object LastWriteTime
)

if ($battleFiles.Count -eq 0) {
    throw 'No RPG battle logs found.'
}

Write-Host "Battle Logs : $($battleFiles.Count)"

$characters = @{}
$partyHistory = @()
$missionHistory = @()

foreach ($file in $battleFiles) {
    $battle = Read-JsonSafe $file.FullName
    if ($null -eq $battle) { continue }

    $runId = [string](Get-Prop $battle 'run_id' $file.BaseName)
    $missionResult = [string](Get-Prop $battle 'mission_result' 'MISSION_HOLD')
    $finalScore = [double](Get-Prop $battle 'final_score' 0)

    $party = Get-Prop $battle 'party' $null
    $partyModel = [string](Get-Prop $party 'model' '')
    $partyTier = [string](Get-Prop $party 'tier' (Get-ModelTier $partyModel))
    $logicalSize = [int](Get-Prop $party 'logical_size' 0)
    $stableWidth = [int](Get-Prop $party 'stable_physical_width' 0)
    $probeWidth = [int](Get-Prop $party 'next_probe_width' 0)
    $partyCharacters = @(Get-Prop $party 'characters' @())

    $clear = ($missionResult -eq 'MISSION_CLEAR')

    foreach ($c in $partyCharacters) {
        $id = [string](Get-Prop $c 'character_id' '')
        if ([string]::IsNullOrWhiteSpace($id)) { continue }

        $display = [string](Get-Prop $c 'display_name' $id)
        $class = [string](Get-Prop $c 'class' (Get-Class $display))
        $model = [string](Get-Prop $c 'model' $partyModel)
        $tier = [string](Get-Prop $c 'model_tier' $partyTier)

        Ensure-CharacterProfile `
            -Profiles $characters `
            -CharacterId $id `
            -DisplayName $display `
            -Class $class `
            -Model $model `
            -ModelTier $tier

        $profile = $characters[$id]

        $stats = Get-Prop $c 'measured_stats' $null
        $latency = [double](Get-Prop $stats 'latency_ms' 0)
        $status = [string](Get-Prop $c 'status' 'READY')
        $success = ($status -eq 'READY')

        $profile.evidence.missions += 1
        $profile.evidence.measured_samples += 1
        $profile.evidence.total_latency_ms += $latency

        if ($success) {
            $profile.evidence.successes += 1
        }
        else {
            $profile.evidence.failures += 1
        }

        $baseXp = 100.0
        $missionXp = if ($clear) { 150.0 } else { 50.0 }
        $successXp = if ($success) { 100.0 } else { 0.0 }
        $efficiencyXp = (Get-LatencyEfficiency $latency) * 50.0

        $earned = $baseXp + $missionXp + $successXp + $efficiencyXp
        $profile.progression.xp += [math]::Round($earned,2)

        Add-RoleAffinity -Profile $profile -Role $display -Value $(if ($success) { 2 } else { 1 })
    }

    $command = Get-Prop $battle 'command' $null
    $integratorModel = [string](Get-Prop $command 'integrator' '')
    $integratorGreen = [bool](Get-Prop $command 'integrator_green' $false)
    $escalationUsed = [bool](Get-Prop $command 'escalation_used' $false)
    $finalModel = [string](Get-Prop $command 'final_model' $integratorModel)

    if (-not [string]::IsNullOrWhiteSpace($integratorModel)) {
        $integratorId = "INTEGRATOR::$integratorModel"

        Ensure-CharacterProfile `
            -Profiles $characters `
            -CharacterId $integratorId `
            -DisplayName 'Integrator' `
            -Class 'COMMANDER' `
            -Model $integratorModel `
            -ModelTier (Get-ModelTier $integratorModel)

        $p = $characters[$integratorId]
        $p.evidence.missions += 1
        $p.evidence.measured_samples += 1

        if ($integratorGreen) {
            $p.evidence.successes += 1
            $p.progression.xp += 400.0
            $p.affinities.integration += 3
        }
        else {
            $p.evidence.failures += 1
            $p.progression.xp += 150.0
            $p.affinities.integration += 1
        }
    }

    if ($escalationUsed -and -not [string]::IsNullOrWhiteSpace($finalModel)) {
        $reviewId = "REVIEWER::$finalModel"

        Ensure-CharacterProfile `
            -Profiles $characters `
            -CharacterId $reviewId `
            -DisplayName 'Senior Reviewer' `
            -Class 'REVIEWER' `
            -Model $finalModel `
            -ModelTier (Get-ModelTier $finalModel)

        $p = $characters[$reviewId]
        $p.evidence.missions += 1
        $p.evidence.successes += $(if ($clear) { 1 } else { 0 })
        $p.evidence.failures += $(if ($clear) { 0 } else { 1 })
        $p.progression.xp += $(if ($clear) { 450.0 } else { 175.0 })
        $p.affinities.review += 3
    }

    $partyHistory += [ordered]@{
        run_id=$runId
        result=$missionResult
        score=$finalScore
        model=$partyModel
        logical_size=$logicalSize
        stable_width=$stableWidth
        probe_width=$probeWidth
        integrator=$integratorModel
        integrator_green=$integratorGreen
        escalation_used=$escalationUsed
        final_model=$finalModel
    }

    $missionHistory += [ordered]@{
        run_id=$runId
        clear=$clear
        final_score=$finalScore
    }
}

# Finalize character progression.
$characterList = @()

foreach ($key in $characters.Keys) {
    $p = $characters[$key]

    $missions = [int]$p.evidence.missions
    $successes = [int]$p.evidence.successes

    $successRate = if ($missions -gt 0) {
        [math]::Round($successes / [double]$missions,3)
    } else {
        0.0
    }

    $avgLatency = if ($p.evidence.measured_samples -gt 0) {
        [math]::Round(
            $p.evidence.total_latency_ms / [double]$p.evidence.measured_samples,
            1
        )
    } else {
        0.0
    }

    $level = Get-LevelFromXp $p.progression.xp
    $rank = Get-Rank -Level $level -SuccessRate $successRate

    $p.progression.level = $level
    $p.progression.rank = $rank
    $p.evidence | Add-Member -NotePropertyName success_rate -NotePropertyValue $successRate -Force
    $p.evidence | Add-Member -NotePropertyName average_latency_ms -NotePropertyValue $avgLatency -Force

    $characterList += [pscustomobject]$p

    $safeId = ($p.character_id -replace '[\\/:*?"<>|]','_')
    Write-Json (Join-Path $characterRoot "$safeId.json") $p
}

# Party progression derived from real mission history.
$totalMissions = $missionHistory.Count
$totalClears = @($missionHistory | Where-Object { $_.clear }).Count
$clearRate = if ($totalMissions -gt 0) {
    [math]::Round($totalClears / [double]$totalMissions,3)
} else {
    0.0
}

$stableWidths = @(
    $partyHistory |
    Where-Object { $_.result -eq 'MISSION_CLEAR' -and $_.stable_width -gt 0 } |
    ForEach-Object { [int]$_.stable_width } |
    Sort-Object
)

$recommendedWidth = 1
if ($stableWidths.Count -gt 0) {
    $recommendedWidth = $stableWidths[[math]::Floor(($stableWidths.Count - 1) / 2)]
}

$partyXp = (
    ($totalMissions * 150.0) +
    ($totalClears * 350.0) +
    ($clearRate * 500.0)
)

$partyLevel = Get-LevelFromXp $partyXp
$partyRank = Get-Rank -Level $partyLevel -SuccessRate $clearRate

$partyProfile = [ordered]@{
    schema='vertex.world.rpg.party-progression.v1'
    updated_at=(Get-Date).ToString('o')

    party_id='ARD_CORE_PARTY'

    progression=[ordered]@{
        xp=[math]::Round($partyXp,2)
        level=$partyLevel
        rank=$partyRank
    }

    evidence=[ordered]@{
        missions=$totalMissions
        clears=$totalClears
        clear_rate=$clearRate
        recommended_parallel_width=$recommendedWidth
    }

    history=$partyHistory
}

$partyPath = Join-Path $partyRoot 'ARD_CORE_PARTY.json'
Write-Json $partyPath $partyProfile

$worldProgression = [ordered]@{
    schema='vertex.world.rpg.progression-index.v1'
    updated_at=(Get-Date).ToString('o')

    world=[ordered]@{
        missions=$totalMissions
        clears=$totalClears
        clear_rate=$clearRate
    }

    party=$partyProfile
    characters=@($characterList | Sort-Object { $_.progression.level } -Descending)
}

$progressionPath = Join-Path $progressionRoot 'VERTEX_WORLD_PROGRESSION.json'
Write-Json $progressionPath $worldProgression

$receipt = [ordered]@{
    schema='vertex.world.rpg.progression-engine-receipt.v1'
    completed_at=(Get-Date).ToString('o')
    battle_logs_processed=$battleFiles.Count
    characters=$characterList.Count
    missions=$totalMissions
    clears=$totalClears
    party_level=$partyLevel
    party_rank=$partyRank
    recommended_parallel_width=$recommendedWidth
    outputs=@(
        $progressionPath,
        $partyPath,
        $characterRoot
    )
    canonical_mutation='NONE'
    vtc_execution='NONE'
}

$receiptPath = Join-Path $receiptRoot "RPG_PROGRESSION_ENGINE.$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"
Write-Json $receiptPath $receipt

Write-Host ''
Write-Host '[WORLD PROGRESSION]' -ForegroundColor Cyan
Write-Host "  Missions       : $totalMissions"
Write-Host "  Clears         : $totalClears"
Write-Host "  Clear Rate     : $clearRate"
Write-Host "  Party Level    : $partyLevel"
Write-Host "  Party Rank     : $partyRank"
Write-Host "  Recommended W  : $recommendedWidth"

Write-Host ''
Write-Host '[CHARACTERS]' -ForegroundColor Cyan

$characterList |
    Sort-Object { $_.progression.level } -Descending |
    ForEach-Object {
        Write-Host ("  {0,-18} Lv.{1,-3} Rank {2}  XP={3}" -f `
            $_.display_name,
            $_.progression.level,
            $_.progression.rank,
            [math]::Round($_.progression.xp,0)
        )
    }

Write-Host ''
Write-Host "Progression : $progressionPath"
Write-Host "Party       : $partyPath"
Write-Host "Characters  : $characterRoot"
Write-Host "Receipt     : $receiptPath"

Write-Host ''
Write-Host 'RPG PROGRESSION IS DERIVED FROM REAL EXECUTION EVIDENCE.'
Write-Host 'CANONICAL MUTATION : NONE'
Write-Host 'VTC EXECUTION      : NONE'
Write-Host ''
Write-Host 'VERTEX WORLD — PROGRESSION ONLINE.'
Write-Host '轟。' -ForegroundColor Green
