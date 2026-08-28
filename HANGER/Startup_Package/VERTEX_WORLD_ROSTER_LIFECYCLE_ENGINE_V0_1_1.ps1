#requires -Version 7.0
<#
VERTEX WORLD — ROSTER LIFECYCLE ENGINE V0.1.1

PURPOSE
  Build an evidence-driven ARD roster lifecycle:
    - STARTER
    - BENCH
    - RESERVE
    - TRIAL
    - PROMOTION
    - DEMOTION
    - RETENTION
    - GENERATION CHANGE

INPUTS
  - Progression
  - Synergy/Affinity
  - Confidence
  - Current Formation

NO EXECUTION
  This engine changes only roster metadata.
  It does NOT invoke models or agents.

SAFETY
  - No canonical mutation.
  - No VTC execution.
  - No model invocation.
  - No agent execution.
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

$progressionPath = Join-Path $rpgRoot 'progression\VERTEX_WORLD_PROGRESSION.json'
$confidencePath = Join-Path $rpgRoot 'confidence\VERTEX_WORLD_AFFINITY_CONFIDENCE.json'
$formationPath = Join-Path $rpgRoot 'formations\CURRENT_FORMATION_PLAN.json'

$rosterRoot = Join-Path $rpgRoot 'roster'
$historyRoot = Join-Path $rosterRoot 'history'
$receiptRoot = Join-Path $rpgRoot 'receipts'

@($rosterRoot,$historyRoot,$receiptRoot) | ForEach-Object {
    $null = New-Item -ItemType Directory -Force -Path $_
}

function Banner([string]$Text) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Magenta
    Write-Host " $Text" -ForegroundColor Magenta
    Write-Host '============================================================' -ForegroundColor Magenta
}

function Write-Json([string]$Path,$Object) {
    $Object | ConvertTo-Json -Depth 100 |
        Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-Prop {
    param($Object,[string]$Name,$Default=$null)

    if ($null -eq $Object) { return $Default }

    $p = $Object.PSObject.Properties[$Name]

    if ($null -eq $p -or $null -eq $p.Value) {
        return $Default
    }

    return $p.Value
}

function Get-ConfidenceEntry {
    param(
        [array]$Entries,
        [string]$Role
    )

    return $Entries |
        Where-Object {
            [string](Get-Prop $_ 'role' '') -eq $Role
        } |
        Select-Object -First 1
}

function Get-RosterState {
    param(
        [int]$Level,
        [string]$Rank,
        [double]$ConservativeAffinity,
        [string]$ConfidenceTier,
        [int]$Samples,
        [bool]$InCurrentFormation
    )

    if ($Samples -eq 0) {
        return 'TRIAL'
    }

    if (
        $InCurrentFormation -and
        $ConservativeAffinity -ge 55
    ) {
        return 'STARTER'
    }

    if (
        $Samples -ge 5 -and
        $ConservativeAffinity -ge 65
    ) {
        return 'STARTER'
    }

    if (
        $ConservativeAffinity -ge 50 -or
        $Level -ge 2
    ) {
        return 'BENCH'
    }

    return 'RESERVE'
}

function Get-PriorityScore {
    param(
        [int]$Level,
        [double]$Xp,
        [double]$SuccessRate,
        [double]$Affinity,
        [string]$ConfidenceTier,
        [bool]$InCurrentFormation
    )

    $confidenceMult = switch ($ConfidenceTier) {
        'ESTABLISHED' { 1.00 }
        'TRUSTED'     { 0.95 }
        'EMERGING'    { 0.85 }
        'PROVISIONAL' { 0.70 }
        default       { 0.60 }
    }

    $xpNorm = [math]::Min(1.0,$Xp / 5000.0)
    $levelNorm = [math]::Min(1.0,$Level / 20.0)
    $formationBoost = if ($InCurrentFormation) { 0.08 } else { 0.0 }

    $score = (
        ($levelNorm * 0.20) +
        ($xpNorm * 0.15) +
        ($SuccessRate * 0.25) +
        (($Affinity / 100.0) * 0.32) +
        $formationBoost
    ) * $confidenceMult

    return [math]::Round($score,4)
}


function Test-IsCommandStaff {
    param(
        [string]$DisplayName,
        [string]$Class,
        [string]$CharacterId
    )

    if ($Class -in @('COMMANDER','REVIEWER','ARCHITECT')) { return $true }
    if ($DisplayName -in @('Integrator','Senior Reviewer','Commander','Architect')) { return $true }
    if ($CharacterId -match '^(INTEGRATOR|REVIEWER|COMMANDER|ARCHITECT)::') { return $true }

    return $false
}

function Get-CommandStaffState {
    param(
        [int]$Missions,
        [double]$SuccessRate,
        [double]$Xp,
        [int]$Level
    )

    if ($Missions -le 0) { return 'TRIAL_STAFF' }
    if ($Missions -ge 2 -and $SuccessRate -ge 0.80) { return 'ACTIVE_STAFF' }
    if ($Missions -ge 1) { return 'PROBATIONARY_STAFF' }

    return 'TRIAL_STAFF'
}

function Get-CommandPriority {
    param(
        [int]$Missions,
        [double]$SuccessRate,
        [double]$Xp,
        [int]$Level
    )

    $missionNorm = [math]::Min(1.0,$Missions / 20.0)
    $xpNorm = [math]::Min(1.0,$Xp / 5000.0)
    $levelNorm = [math]::Min(1.0,$Level / 20.0)

    $score = (
        ($SuccessRate * 0.45) +
        ($missionNorm * 0.20) +
        ($xpNorm * 0.20) +
        ($levelNorm * 0.15)
    )

    return [math]::Round($score,4)
}

Banner 'VERTEX WORLD — ROSTER LIFECYCLE ENGINE V0.1.1'

$progression = Read-JsonSafe $progressionPath
$confidence = Read-JsonSafe $confidencePath
$formation = Read-JsonSafe $formationPath

if ($null -eq $progression) {
    throw "Progression data not found: $progressionPath"
}

if ($null -eq $confidence) {
    throw "Confidence data not found: $confidencePath"
}

$characters = @(Get-Prop $progression 'characters' @())
$roleConfidence = @(Get-Prop $confidence 'role_affinity' @())

$currentRoles = @()

if ($null -ne $formation) {
    $party = Get-Prop $formation 'party' $null
    $currentRoles = @(
        Get-Prop $party 'roles' @() |
        ForEach-Object {
            [string](Get-Prop $_ 'role' '')
        }
    )
}

$previousRosterPath = Join-Path $rosterRoot 'CURRENT_ROSTER.json'
$previousRoster = Read-JsonSafe $previousRosterPath
$previousMembers = @()

if ($null -ne $previousRoster) {
    $previousMembers = @(Get-Prop $previousRoster 'field_members' (Get-Prop $previousRoster 'members' @()))
}

$fieldMembers = @()
$commandStaff = @()

foreach ($c in $characters) {
    $display = [string](Get-Prop $c 'display_name' '')
    $class = [string](Get-Prop $c 'class' 'AGENT')
    $model = [string](Get-Prop $c 'model' '')
    $tier = [string](Get-Prop $c 'model_tier' 'UNKNOWN')

    $prog = Get-Prop $c 'progression' $null
    $level = [int](Get-Prop $prog 'level' 1)
    $rank = [string](Get-Prop $prog 'rank' 'E')
    $xp = [double](Get-Prop $prog 'xp' 0)

    $evidence = Get-Prop $c 'evidence' $null
    $missions = [int](Get-Prop $evidence 'missions' 0)
    $successRate = [double](Get-Prop $evidence 'success_rate' 0)

    $confEntry = Get-ConfidenceEntry `
        -Entries $roleConfidence `
        -Role $display

    $conservative = 50.0
    $confidenceTier = 'PROVISIONAL'
    $samples = 0

    if ($null -ne $confEntry) {
        $conf = Get-Prop $confEntry 'confidence' $null

        $conservative = [double](
            Get-Prop $conf 'conservative_score' 50
        )

        $confidenceTier = [string](
            Get-Prop $conf 'confidence_tier' 'PROVISIONAL'
        )

        $samples = [int](
            Get-Prop $confEntry 'samples' 0
        )
    }

    $inCurrentFormation = ($currentRoles -contains $display)

    $state = Get-RosterState `
        -Level $level `
        -Rank $rank `
        -ConservativeAffinity $conservative `
        -ConfidenceTier $confidenceTier `
        -Samples $samples `
        -InCurrentFormation $inCurrentFormation

    $priority = Get-PriorityScore `
        -Level $level `
        -Xp $xp `
        -SuccessRate $successRate `
        -Affinity $conservative `
        -ConfidenceTier $confidenceTier `
        -InCurrentFormation $inCurrentFormation

    $previousState = ''

    $prev = $previousMembers |
        Where-Object {
            [string](Get-Prop $_ 'display_name' '') -eq $display
        } |
        Select-Object -First 1

    if ($null -ne $prev) {
        $previousState = [string](
            Get-Prop $prev 'roster_state' ''
        )
    }

    $transition = 'INITIAL_PLACEMENT'

    if (-not [string]::IsNullOrWhiteSpace($previousState)) {
        if ($previousState -eq $state) {
            $transition = 'RETAIN'
        }
        else {
            $order = @{
                'TRIAL'=0
                'RESERVE'=1
                'BENCH'=2
                'STARTER'=3
            }

            if ($order[$state] -gt $order[$previousState]) {
                $transition = 'PROMOTION'
            }
            elseif ($order[$state] -lt $order[$previousState]) {
                $transition = 'DEMOTION'
            }
            else {
                $transition = 'ROLE_CHANGE'
            }
        }
    }

    $characterId = [string](Get-Prop $c 'character_id' '')
    $isCommandStaff = Test-IsCommandStaff `
        -DisplayName $display `
        -Class $class `
        -CharacterId $characterId

    if ($isCommandStaff) {
        $staffState = Get-CommandStaffState `
            -Missions $missions `
            -SuccessRate $successRate `
            -Xp $xp `
            -Level $level

        $staffPriority = Get-CommandPriority `
            -Missions $missions `
            -SuccessRate $successRate `
            -Xp $xp `
            -Level $level

        $commandStaff += [ordered]@{
            character_id=$characterId
            display_name=$display
            class=$class
            model=$model
            model_tier=$tier

            staff_state=$staffState
            priority_score=$staffPriority

            progression=[ordered]@{
                level=$level
                rank=$rank
                xp=$xp
            }

            evidence=[ordered]@{
                missions=$missions
                success_rate=$successRate
                role='COMMAND_STAFF'
            }
        }
    }
    else {
        $fieldMembers += [ordered]@{
            character_id=$characterId
            display_name=$display
            class=$class
            model=$model
            model_tier=$tier

            roster_state=$state
            transition=$transition
            previous_state=$previousState

            priority_score=$priority

            progression=[ordered]@{
                level=$level
                rank=$rank
                xp=$xp
            }

            evidence=[ordered]@{
                missions=$missions
                success_rate=$successRate
                affinity_conservative=$conservative
                confidence_tier=$confidenceTier
                affinity_samples=$samples
                in_current_formation=$inCurrentFormation
            }
        }
    }
}

# Sort by operational priority.
$fieldMembers = @(
    $fieldMembers |
    Sort-Object `
        @{Expression='roster_state'; Descending=$true},
        @{Expression='priority_score'; Descending=$true}
)

$commandStaff = @(
    $commandStaff |
    Sort-Object `
        @{Expression='priority_score'; Descending=$true}
)

$starters = @(
    $fieldMembers |
    Where-Object { $_.roster_state -eq 'STARTER' }
)

$bench = @(
    $fieldMembers |
    Where-Object { $_.roster_state -eq 'BENCH' }
)

$reserve = @(
    $fieldMembers |
    Where-Object { $_.roster_state -eq 'RESERVE' }
)

$trial = @(
    $fieldMembers |
    Where-Object { $_.roster_state -eq 'TRIAL' }
)

$promotions = @(
    $fieldMembers |
    Where-Object { $_.transition -eq 'PROMOTION' }
)

$demotions = @(
    $fieldMembers |
    Where-Object { $_.transition -eq 'DEMOTION' }
)

$generation = 1

if ($null -ne $previousRoster) {
    $generation = [int](
        Get-Prop $previousRoster 'generation' 1
    )

    if ($promotions.Count -gt 0 -or $demotions.Count -gt 0) {
        $generation++
    }
}

$roster = [ordered]@{
    schema='vertex.world.rpg.roster-lifecycle.v1.1'
    updated_at=(Get-Date).ToString('o')
    generation=$generation

    counts=[ordered]@{
        total=($fieldMembers.Count + $commandStaff.Count)
        field_total=$fieldMembers.Count
        command_staff=$commandStaff.Count
        starters=$starters.Count
        bench=$bench.Count
        reserve=$reserve.Count
        trial=$trial.Count
        promotions=$promotions.Count
        demotions=$demotions.Count
    }

    field_roster=[ordered]@{
        starters=$starters
        bench=$bench
        reserve=$reserve
        trial=$trial
        promotions=$promotions
        demotions=$demotions
        members=$fieldMembers
    }

    command_staff=[ordered]@{
        members=$commandStaff
    }

    # Backward-compatible alias for field roster consumers.
    members=$fieldMembers

    policy=[ordered]@{
        note='Field roster and command staff are evaluated on different evidence axes.'
        automatic_model_execution=$false
        auto_party_formation_may_read_roster=$true
        human_override_allowed=$true
    }
}

$currentRosterPath = Join-Path $rosterRoot 'CURRENT_ROSTER.json'
Write-Json $currentRosterPath $roster

$historyPath = Join-Path $historyRoot "ROSTER_GENERATION_$generation.$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"
Write-Json $historyPath $roster

$receiptPath = Join-Path $receiptRoot "ROSTER_LIFECYCLE.$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"

Write-Json $receiptPath ([ordered]@{
    schema='vertex.world.rpg.roster-lifecycle-receipt.v1.1'
    completed_at=(Get-Date).ToString('o')
    generation=$generation
    total=($fieldMembers.Count + $commandStaff.Count)
    field_total=$fieldMembers.Count
    command_staff=$commandStaff.Count
    starters=$starters.Count
    bench=$bench.Count
    reserve=$reserve.Count
    trial=$trial.Count
    promotions=$promotions.Count
    demotions=$demotions.Count
    roster=$currentRosterPath
    canonical_mutation='NONE'
    vtc_execution='NONE'
    agent_execution='NONE'
})

Write-Host ''
Write-Host '[STARTERS]' -ForegroundColor Cyan

if ($starters.Count -eq 0) {
    Write-Host '  <none>'
}
else {
    foreach ($m in $starters) {
        Write-Host (
            "  {0,-16} Lv.{1,-3} Rank {2} priority={3} confidence={4}" -f `
            $m.display_name,
            $m.progression.level,
            $m.progression.rank,
            $m.priority_score,
            $m.evidence.confidence_tier
        )
    }
}

Write-Host ''
Write-Host '[BENCH]' -ForegroundColor Cyan

if ($bench.Count -eq 0) {
    Write-Host '  <none>'
}
else {
    foreach ($m in $bench) {
        Write-Host (
            "  {0,-16} Lv.{1,-3} priority={2}" -f `
            $m.display_name,
            $m.progression.level,
            $m.priority_score
        )
    }
}

Write-Host ''
Write-Host '[RESERVE / TRIAL]' -ForegroundColor Cyan

foreach ($m in @($reserve + $trial)) {
    Write-Host (
        "  {0,-16} {1} priority={2}" -f `
        $m.display_name,
        $m.roster_state,
        $m.priority_score
    )
}

Write-Host ''
Write-Host '[COMMAND STAFF]' -ForegroundColor Cyan

if ($commandStaff.Count -eq 0) {
    Write-Host '  <none>'
}
else {
    foreach ($m in $commandStaff) {
        Write-Host (
            "  {0,-18} {1,-20} model={2} priority={3}" -f `
            $m.display_name,
            $m.staff_state,
            $m.model,
            $m.priority_score
        )
    }
}

Write-Host ''
Write-Host '[TRANSITIONS]' -ForegroundColor Cyan

if ($promotions.Count -eq 0 -and $demotions.Count -eq 0) {
    Write-Host '  No promotion/demotion this generation.'
}
else {
    foreach ($m in $promotions) {
        Write-Host "  PROMOTION : $($m.display_name) $($m.previous_state) -> $($m.roster_state)" -ForegroundColor Green
    }

    foreach ($m in $demotions) {
        Write-Host "  DEMOTION  : $($m.display_name) $($m.previous_state) -> $($m.roster_state)" -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host '[ROSTER]' -ForegroundColor Cyan
Write-Host "  Generation : $generation"
Write-Host "  Total      : $(($fieldMembers.Count + $commandStaff.Count))"
Write-Host "  Field      : $($fieldMembers.Count)"
Write-Host "  Command    : $($commandStaff.Count)"
Write-Host "  Starters   : $($starters.Count)"
Write-Host "  Bench      : $($bench.Count)"
Write-Host "  Reserve    : $($reserve.Count)"
Write-Host "  Trial      : $($trial.Count)"

Write-Host ''
Write-Host "Current Roster : $currentRosterPath"
Write-Host "History        : $historyPath"
Write-Host "Receipt        : $receiptPath"

Write-Host ''
Write-Host 'ROSTER MOVEMENT IS DERIVED FROM EXECUTION EVIDENCE.'
Write-Host 'AUTO EXECUTION      : DISABLED'
Write-Host 'CANONICAL MUTATION  : NONE'
Write-Host 'VTC EXECUTION       : NONE'
Write-Host 'AGENT EXECUTION     : NONE'
Write-Host ''
Write-Host 'VERTEX WORLD — ROSTER ONLINE.'
Write-Host '轟。' -ForegroundColor Green
