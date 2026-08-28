#requires -Version 7.0
<#
VERTEX WORLD — AUTO PARTY FORMATION ENGINE V0.1.2

PURPOSE
  Build an evidence-driven ARD party formation plan from:
    - RPG Progression
    - Synergy/Affinity
    - Confidence Layer
    - Stable Parallel Width
    - Integrator Compatibility

IMPORTANT
  This engine DOES NOT execute agents.
  It produces a formation plan only.

SAFETY
  - No model invocation.
  - No OS mutation.
  - No canonical mutation.
  - No VTC execution.
  - No agent execution.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'G:\Vertex_Project\Vertex_Studio_AI',
    [string]$VxnRoot = '',

    [ValidateSet(
        'GENERAL',
        'CODING',
        'MEMORY_RECALL',
        'TRANSACTION_SAFETY',
        'UI_LOCK_SCOPE',
        'REVIEW'
    )]
    [string]$MissionClass = 'GENERAL',

    [int]$DesiredPartySize = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VxnRoot)) {
    $VxnRoot = Join-Path $ProjectRoot 'VXN'
}

$rpgRoot = Join-Path $VxnRoot 'runtime\rpg'
$progressionPath = Join-Path $rpgRoot 'progression\VERTEX_WORLD_PROGRESSION.json'
$synergyPath = Join-Path $rpgRoot 'synergy\VERTEX_WORLD_SYNERGY_AFFINITY.json'
$confidencePath = Join-Path $rpgRoot 'confidence\VERTEX_WORLD_AFFINITY_CONFIDENCE.json'
$partyPath = Join-Path $rpgRoot 'parties\ARD_CORE_PARTY.json'
$commandStaffPath = Join-Path $rpgRoot 'command_staff\CURRENT_COMMAND_STAFF.json'
$rosterPath = Join-Path $rpgRoot 'roster\CURRENT_ROSTER.json'

$formationRoot = Join-Path $rpgRoot 'formations'
$receiptRoot = Join-Path $rpgRoot 'receipts'

$null = New-Item -ItemType Directory -Force -Path $formationRoot
$null = New-Item -ItemType Directory -Force -Path $receiptRoot

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$formationId = "ARD-FORMATION-$MissionClass-$stamp"

function Banner([string]$Text) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Magenta
    Write-Host " $Text" -ForegroundColor Magenta
    Write-Host '============================================================' -ForegroundColor Magenta
}

function Write-Json([string]$Path, $Object) {
    $parent = Split-Path -Parent $Path
    if ($parent) {
        $null = New-Item -ItemType Directory -Force -Path $parent
    }

    $Object | ConvertTo-Json -Depth 100 |
        Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-Prop {
    param(
        $Object,
        [string]$Name,
        $Default=$null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $p = $Object.PSObject.Properties[$Name]

    if ($null -eq $p -or $null -eq $p.Value) {
        return $Default
    }

    return $p.Value
}

function Clamp01([double]$Value) {
    return [math]::Max(0.0,[math]::Min(1.0,$Value))
}

function Get-LMStudioModels {
    try {
        $r = Invoke-RestMethod `
            -Method Get `
            -Uri 'http://127.0.0.1:1234/v1/models' `
            -TimeoutSec 5

        return @(
            $r.data |
            ForEach-Object { [string]$_.id } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }
    catch {
        return @()
    }
}

function Get-ModelSizeInfo {
    param([string]$ModelId)

    $id = $ModelId.ToLowerInvariant()

    # Exclude MoE active-parameter notation (a4b/a3b) from total-size detection.
    $clean = $id -replace '(?i)a\d+(?:\.\d+)?b', ''

    $matches = [regex]::Matches(
        $clean,
        '(?<![a-z0-9])(\d+(?:\.\d+)?)b(?![a-z0-9])'
    )

    $sizes = @()

    foreach ($m in $matches) {
        $v = 0.0
        if ([double]::TryParse($m.Groups[1].Value,[ref]$v)) {
            $sizes += $v
        }
    }

    if ($sizes.Count -eq 0) {
        return [pscustomobject]@{
            Model=$ModelId
            PrimarySize=$null
        }
    }

    return [pscustomobject]@{
        Model=$ModelId
        PrimarySize=[double](($sizes | Measure-Object -Maximum).Maximum)
    }
}

function Select-RookieModel {
    param(
        [string[]]$Models,
        [string]$Role,
        [string]$MissionClass
    )

    $candidates = @()

    foreach ($model in $Models) {
        $info = Get-ModelSizeInfo -ModelId $model

        if ($null -eq $info.PrimarySize) {
            continue
        }

        $size = [double]$info.PrimarySize

        # Rookie Draft prefers cheap/local small models first.
        if ($size -ge 2.5 -and $size -le 4.5) {
            $score = 1.0

            # Minor role-sensitive preferences without claiming proven affinity.
            if ($Role -eq 'Verifier' -and $model -match '(?i)instruct|reason|qwen|gemma|hunyuan') {
                $score += 0.10
            }

            if ($Role -eq 'Optimizer' -and $model -match '(?i)coder|code') {
                $score += 0.12
            }

            if ($MissionClass -eq 'TRANSACTION_SAFETY' -and $model -match '(?i)instruct|reason') {
                $score += 0.08
            }

            $candidates += [pscustomobject]@{
                Model=$model
                Size=$size
                Score=$score
            }
        }
    }

    if ($candidates.Count -eq 0) {
        return ''
    }

    return [string]((
        $candidates |
        Sort-Object `
            @{Expression='Score'; Descending=$true},
            @{Expression='Size'; Ascending=$true},
            @{Expression='Model'; Ascending=$true} |
        Select-Object -First 1
    ).Model)
}

function Get-MissionRoleWeights([string]$Class) {
    switch ($Class) {

        'CODING' {
            return [ordered]@{
                Planner=1.00
                Critic=0.80
                ScopeGuard=0.65
                Explorer=0.55
                Verifier=0.85
                Optimizer=0.90
            }
        }

        'MEMORY_RECALL' {
            return [ordered]@{
                Explorer=1.00
                Planner=0.70
                Critic=0.65
                ScopeGuard=0.70
                Verifier=0.95
                Optimizer=0.40
            }
        }

        'TRANSACTION_SAFETY' {
            return [ordered]@{
                ScopeGuard=1.00
                Critic=0.95
                Verifier=0.95
                Planner=0.80
                Explorer=0.45
                Optimizer=0.30
            }
        }

        'UI_LOCK_SCOPE' {
            return [ordered]@{
                ScopeGuard=1.00
                Planner=0.85
                Critic=0.80
                Verifier=0.75
                Explorer=0.40
                Optimizer=0.35
            }
        }

        'REVIEW' {
            return [ordered]@{
                Critic=1.00
                Verifier=1.00
                ScopeGuard=0.90
                Planner=0.60
                Explorer=0.55
                Optimizer=0.45
            }
        }

        default {
            return [ordered]@{
                Explorer=0.80
                Planner=0.90
                Critic=0.85
                ScopeGuard=0.85
                Verifier=0.75
                Optimizer=0.65
            }
        }
    }
}

function Get-ConfidenceMultiplier([string]$Tier) {
    switch ($Tier) {
        'ESTABLISHED' { return 1.00 }
        'TRUSTED'     { return 0.92 }
        'EMERGING'    { return 0.80 }
        default       { return 0.60 }
    }
}

function Get-ConservativeScore {
    param(
        [array]$ConfidenceEntries,
        [string]$Role,
        [string]$Model=''
    )

    $match = $null

    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $match = $ConfidenceEntries |
            Where-Object {
                [string](Get-Prop $_ 'role' '') -eq $Role -and
                [string](Get-Prop $_ 'model' '') -eq $Model
            } |
            Select-Object -First 1
    }
    else {
        $match = $ConfidenceEntries |
            Where-Object {
                [string](Get-Prop $_ 'role' '') -eq $Role
            } |
            Select-Object -First 1
    }

    if ($null -eq $match) {
        return [pscustomobject]@{
            Raw=50.0
            Conservative=50.0
            Tier='PROVISIONAL'
            Samples=0
        }
    }

    $confidence = Get-Prop $match 'confidence' $null

    return [pscustomobject]@{
        Raw=[double](Get-Prop $match 'affinity_index' 50)
        Conservative=[double](Get-Prop $confidence 'conservative_score' 50)
        Tier=[string](Get-Prop $confidence 'confidence_tier' 'PROVISIONAL')
        Samples=[int](Get-Prop $match 'samples' 0)
    }
}

function Get-RoleCharacter {
    param(
        [array]$Characters,
        [string]$Role
    )

    $match = $Characters |
        Where-Object {
            [string](Get-Prop $_ 'display_name' '') -eq $Role
        } |
        Sort-Object {
            [double](Get-Prop (Get-Prop $_ 'progression' $null) 'xp' 0)
        } -Descending |
        Select-Object -First 1

    return $match
}

function Get-PairSynergyScore {
    param(
        [array]$PairEntries,
        [string]$A,
        [string]$B
    )

    $entry = $PairEntries |
        Where-Object {
            (
                [string](Get-Prop $_ 'role_a' '') -eq $A -and
                [string](Get-Prop $_ 'role_b' '') -eq $B
            ) -or (
                [string](Get-Prop $_ 'role_a' '') -eq $B -and
                [string](Get-Prop $_ 'role_b' '') -eq $A
            )
        } |
        Select-Object -First 1

    if ($null -eq $entry) {
        return 50.0
    }

    $confidence = Get-Prop $entry 'confidence' $null
    return [double](Get-Prop $confidence 'conservative_score' 50)
}

function Get-IntegratorCandidate {
    param(
        [array]$IntegratorEntries
    )

    $ranked = foreach ($e in $IntegratorEntries) {
        $confidence = Get-Prop $e 'confidence' $null

        [pscustomobject]@{
            PartyModel=[string](Get-Prop $e 'party_model' '')
            IntegratorModel=[string](Get-Prop $e 'integrator_model' '')
            Compatibility=[double](Get-Prop $e 'compatibility_index' 0)
            Conservative=[double](Get-Prop $confidence 'conservative_score' 0)
            Tier=[string](Get-Prop $confidence 'confidence_tier' 'PROVISIONAL')
            Samples=[int](Get-Prop $e 'samples' 0)
        }
    }

    return $ranked |
        Sort-Object Conservative -Descending |
        Select-Object -First 1
}


function Get-StaffTierWeight([string]$Tier) {
    switch ($Tier) {
        'COMMANDER_CLASS' { return 1.00 }
        'SENIOR_STAFF'    { return 0.92 }
        'ACTIVE_STAFF'    { return 0.82 }
        'PROBATIONARY_STAFF' { return 0.62 }
        default           { return 0.50 }
    }
}

function Get-ConfidenceTierWeight([string]$Tier) {
    switch ($Tier) {
        'ESTABLISHED' { return 1.00 }
        'TRUSTED'     { return 0.92 }
        'EMERGING'    { return 0.82 }
        'PROVISIONAL' { return 0.68 }
        default       { return 0.60 }
    }
}

function Get-CurrentRosterState {
    param(
        $RosterIndex,
        [string]$Role
    )

    if ($null -eq $RosterIndex) {
        return 'UNKNOWN'
    }

    $field = Get-Prop $RosterIndex 'field_roster' $null
    $members = @()

    if ($null -ne $field) {
        $members = @(Get-Prop $field 'members' @())
    }
    else {
        $members = @(Get-Prop $RosterIndex 'members' @())
    }

    $entry = $members |
        Where-Object {
            [string](Get-Prop $_ 'display_name' '') -eq $Role
        } |
        Select-Object -First 1

    if ($null -eq $entry) {
        return 'UNKNOWN'
    }

    return [string](Get-Prop $entry 'roster_state' 'UNKNOWN')
}

function Get-RosterMultiplier([string]$RosterState) {
    switch ($RosterState) {
        'STARTER' { return 1.00 }
        'BENCH'   { return 0.86 }
        'RESERVE' { return 0.72 }
        'TRIAL'   { return 0.62 }
        default   { return 0.75 }
    }
}

function Get-CommandAssignment {
    param(
        $CommandStaffIndex,
        [array]$IntegratorConfidence
    )

    $staffEntries = @()

    if ($null -ne $CommandStaffIndex) {
        $staffEntries = @(Get-Prop $CommandStaffIndex 'staff' @())
    }

    $candidates = @()

    foreach ($s in $staffEntries) {
        $model = [string](Get-Prop $s 'model' '')
        $staffTier = [string](Get-Prop $s 'staff_tier' 'PROBATIONARY_STAFF')
        $evidence = Get-Prop $s 'evidence' $null
        $confidence = Get-Prop $s 'confidence' $null

        $evidenceScore = [double](Get-Prop $evidence 'evidence_score' 0)
        $samples = [int](Get-Prop $evidence 'samples' 0)
        $staffConfidenceTier = [string](Get-Prop $confidence 'tier' 'PROVISIONAL')

        $compatEntries = @(
            $IntegratorConfidence |
            Where-Object {
                [string](Get-Prop $_ 'integrator_model' '') -eq $model
            }
        )

        $compatibility = 50.0
        $compatTier = 'PROVISIONAL'
        $compatSamples = 0

        if ($compatEntries.Count -gt 0) {
            $bestCompat = $compatEntries |
                Sort-Object {
                    [double](Get-Prop (Get-Prop $_ 'confidence' $null) 'conservative_score' 0)
                } -Descending |
                Select-Object -First 1

            $cc = Get-Prop $bestCompat 'confidence' $null
            $compatibility = [double](Get-Prop $cc 'conservative_score' 50)
            $compatTier = [string](Get-Prop $cc 'confidence_tier' 'PROVISIONAL')
            $compatSamples = [int](Get-Prop $bestCompat 'samples' 0)
        }

        $staffWeight = Get-StaffTierWeight $staffTier
        $confWeight = Get-ConfidenceTierWeight $staffConfidenceTier
        $compatConfWeight = Get-ConfidenceTierWeight $compatTier

        $sampleDepth = [math]::Min(1.0, $samples / 20.0)

        $score = (
            (($evidenceScore / 100.0) * 0.36) +
            (($compatibility / 100.0) * 0.28) +
            ($staffWeight * 0.18) +
            ($sampleDepth * 0.10) +
            ($confWeight * 0.05) +
            ($compatConfWeight * 0.03)
        )

        $candidates += [pscustomobject]@{
            Role=[string](Get-Prop $s 'role' 'Command Staff')
            StaffClass=[string](Get-Prop $s 'staff_class' 'COMMAND')
            Model=$model
            StaffTier=$staffTier
            EvidenceScore=$evidenceScore
            Samples=$samples
            StaffConfidence=$staffConfidenceTier
            Compatibility=$compatibility
            CompatibilityTier=$compatTier
            CompatibilitySamples=$compatSamples
            CommandScore=[math]::Round($score,4)
        }
    }

    if ($candidates.Count -gt 0) {
        return $candidates |
            Sort-Object CommandScore -Descending |
            Select-Object -First 1
    }

    # Backward-compatible fallback to compatibility-only assignment.
    $fallback = Get-IntegratorCandidate -IntegratorEntries $IntegratorConfidence

    if ($null -eq $fallback) {
        return $null
    }

    return [pscustomobject]@{
        Role='Integrator'
        StaffClass='INTEGRATOR'
        Model=$fallback.IntegratorModel
        StaffTier='UNCLASSIFIED'
        EvidenceScore=50.0
        Samples=$fallback.Samples
        StaffConfidence=$fallback.Tier
        Compatibility=$fallback.Conservative
        CompatibilityTier=$fallback.Tier
        CompatibilitySamples=$fallback.Samples
        CommandScore=[math]::Round(($fallback.Conservative / 100.0),4)
    }
}

Banner 'VERTEX WORLD — AUTO PARTY FORMATION ENGINE V0.1.2'

$progression = Read-JsonSafe $progressionPath
$synergy = Read-JsonSafe $synergyPath
$confidence = Read-JsonSafe $confidencePath
$partyProfile = Read-JsonSafe $partyPath
$commandStaffIndex = Read-JsonSafe $commandStaffPath
$rosterIndex = Read-JsonSafe $rosterPath

$runtimeModels = @(Get-LMStudioModels)


if ($null -eq $progression) {
    throw "Progression data not found: $progressionPath"
}

if ($null -eq $synergy) {
    throw "Synergy data not found: $synergyPath"
}

if ($null -eq $confidence) {
    throw "Confidence data not found: $confidencePath"
}

$characters = @(Get-Prop $progression 'characters' @())
$roleConfidence = @(Get-Prop $confidence 'role_affinity' @())
$modelRoleConfidence = @(Get-Prop $confidence 'model_role_affinity' @())
$pairConfidence = @(Get-Prop $confidence 'pair_synergy' @())
$formationConfidence = @(Get-Prop $confidence 'formation_affinity' @())
$integratorConfidence = @(Get-Prop $confidence 'integrator_compatibility' @())

$weights = Get-MissionRoleWeights $MissionClass

Write-Host "Formation ID   : $formationId"
Write-Host "Mission Class  : $MissionClass"
Write-Host "Desired Party  : $DesiredPartySize"

$roleCandidates = @()

foreach ($roleName in $weights.Keys) {

    $missionWeight = [double]$weights[$roleName]

    $roleEvidence = Get-ConservativeScore `
        -ConfidenceEntries $roleConfidence `
        -Role $roleName

    $character = Get-RoleCharacter `
        -Characters $characters `
        -Role $roleName

    $characterXp = 0.0
    $characterLevel = 1
    $model = ''
    $assignmentType = 'PROVEN'
    $assignmentStatus = 'EXPERIENCED'
    $assignmentConfidence = 'PROVISIONAL'

    if ($null -ne $character) {
        $progress = Get-Prop $character 'progression' $null
        $characterXp = [double](Get-Prop $progress 'xp' 0)
        $characterLevel = [int](Get-Prop $progress 'level' 1)
        $model = [string](Get-Prop $character 'model' '')
    }

    if ([string]::IsNullOrWhiteSpace($model)) {
        $model = Select-RookieModel `
            -Models $runtimeModels `
            -Role $roleName `
            -MissionClass $MissionClass

        $assignmentType = 'TRIAL'
        $assignmentStatus = 'TRIAL_ASSIGNMENT'
        $assignmentConfidence = 'UNPROVEN'
    }

    $modelRoleEvidence = Get-ConservativeScore `
        -ConfidenceEntries $modelRoleConfidence `
        -Role $roleName `
        -Model $model

    if ($assignmentType -eq 'TRIAL') {
        # Do not pretend an untested model-role pairing has evidence.
        $modelRoleEvidence = [pscustomobject]@{
            Raw=50.0
            Conservative=50.0
            Tier='UNPROVEN'
            Samples=0
        }
    }

    $confidenceMultiplier = Get-ConfidenceMultiplier $roleEvidence.Tier
    $rosterState = Get-CurrentRosterState -RosterIndex $rosterIndex -Role $roleName
    $rosterMultiplier = Get-RosterMultiplier $rosterState

    $xpBoost = [math]::Min(
        1.0,
        [math]::Log10([math]::Max(10.0,$characterXp + 10.0)) / 3.0
    )

    $score = (
        ($missionWeight * 0.35) +
        (($roleEvidence.Conservative / 100.0) * 0.30) +
        (($modelRoleEvidence.Conservative / 100.0) * 0.20) +
        ($xpBoost * 0.15)
    ) * $confidenceMultiplier * $rosterMultiplier

    $roleCandidates += [pscustomobject]@{
        Role=$roleName
        Model=$model
        Level=$characterLevel
        XP=$characterXp
        MissionWeight=$missionWeight
        RoleAffinity=$roleEvidence.Conservative
        ModelRoleAffinity=$modelRoleEvidence.Conservative
        Confidence=if ($assignmentType -eq 'TRIAL') { 'UNPROVEN' } else { $roleEvidence.Tier }
        Samples=if ($assignmentType -eq 'TRIAL') { 0 } else { $roleEvidence.Samples }
        AssignmentType=$assignmentType
        AssignmentStatus=$assignmentStatus
        RosterState=$rosterState
        RosterMultiplier=$rosterMultiplier
        BaseScore=[math]::Round($score,4)
    }
}

# Initial ranking
$ranked = @(
    $roleCandidates |
    Sort-Object BaseScore -Descending
)

if ($DesiredPartySize -lt 1) {
    $DesiredPartySize = 1
}

if ($DesiredPartySize -gt $ranked.Count) {
    $DesiredPartySize = $ranked.Count
}

$selected = New-Object System.Collections.Generic.List[object]

foreach ($candidate in $ranked) {
    if ($selected.Count -ge $DesiredPartySize) {
        break
    }

    $synergyBonus = 0.0

    foreach ($existing in $selected) {
        $pairScore = Get-PairSynergyScore `
            -PairEntries $pairConfidence `
            -A $candidate.Role `
            -B $existing.Role

        $synergyBonus += ($pairScore / 100.0)
    }

    if ($selected.Count -gt 0) {
        $synergyBonus = $synergyBonus / $selected.Count
    }

    $finalScore = $candidate.BaseScore + ($synergyBonus * 0.15)

    $selected.Add([pscustomobject]@{
        Role=$candidate.Role
        Model=$candidate.Model
        Level=$candidate.Level
        XP=$candidate.XP
        MissionWeight=$candidate.MissionWeight
        RoleAffinity=$candidate.RoleAffinity
        ModelRoleAffinity=$candidate.ModelRoleAffinity
        Confidence=$candidate.Confidence
        Samples=$candidate.Samples
        AssignmentType=$candidate.AssignmentType
        AssignmentStatus=$candidate.AssignmentStatus
        RosterState=$candidate.RosterState
        RosterMultiplier=$candidate.RosterMultiplier
        BaseScore=$candidate.BaseScore
        SynergyBonus=[math]::Round($synergyBonus,3)
        FormationScore=[math]::Round($finalScore,4)
    })
}

# Recommend physical width from strongest formation evidence.
$bestFormation = $formationConfidence |
    Sort-Object {
        [double](Get-Prop (Get-Prop $_ 'confidence' $null) 'conservative_score' 0)
    } -Descending |
    Select-Object -First 1

$recommendedWidth = 1

if ($null -ne $bestFormation) {
    $recommendedWidth = [int](Get-Prop $bestFormation 'stable_width' 1)
}

if ($recommendedWidth -gt $DesiredPartySize) {
    $recommendedWidth = $DesiredPartySize
}

if ($recommendedWidth -lt 1) {
    $recommendedWidth = 1
}

$commandAssignment = Get-CommandAssignment `
    -CommandStaffIndex $commandStaffIndex `
    -IntegratorConfidence $integratorConfidence

$integratorModel = ''
$integratorScore = 0.0
$integratorTier = 'PROVISIONAL'
$commandStaffTier = 'UNCLASSIFIED'
$commandEvidenceScore = 0.0
$commandScore = 0.0
$commandSamples = 0

if ($null -ne $commandAssignment) {
    $integratorModel = $commandAssignment.Model
    $integratorScore = $commandAssignment.Compatibility
    $integratorTier = $commandAssignment.CompatibilityTier
    $commandStaffTier = $commandAssignment.StaffTier
    $commandEvidenceScore = $commandAssignment.EvidenceScore
    $commandScore = $commandAssignment.CommandScore
    $commandSamples = $commandAssignment.Samples
}

$formationConfidenceTier = 'PROVISIONAL'
$formationConservative = 50.0

if ($null -ne $bestFormation) {
    $fc = Get-Prop $bestFormation 'confidence' $null
    $formationConfidenceTier = [string](Get-Prop $fc 'confidence_tier' 'PROVISIONAL')
    $formationConservative = [double](Get-Prop $fc 'conservative_score' 50)
}

$plan = [ordered]@{
    schema='vertex.world.ard.auto-party-formation.v1.2'
    formation_id=$formationId
    generated_at=(Get-Date).ToString('o')

    mission=[ordered]@{
        class=$MissionClass
        desired_party_size=$DesiredPartySize
    }

    party=[ordered]@{
        roles=@(
            $selected |
            Sort-Object FormationScore -Descending |
            ForEach-Object {
                [ordered]@{
                    role=$_.Role
                    model=$_.Model
                    level=$_.Level
                    xp=$_.XP
                    confidence=$_.Confidence
                    evidence_samples=$_.Samples
                    assignment_type=$_.AssignmentType
                    assignment_status=$_.AssignmentStatus
                    roster_state=$_.RosterState
                    roster_multiplier=$_.RosterMultiplier
                    role_affinity=$_.RoleAffinity
                    model_role_affinity=$_.ModelRoleAffinity
                    synergy_bonus=$_.SynergyBonus
                    formation_score=$_.FormationScore
                }
            }
        )

        physical_parallel_width=$recommendedWidth

        formation_evidence=[ordered]@{
            conservative_score=$formationConservative
            confidence_tier=$formationConfidenceTier
        }
    }

    command=[ordered]@{
        integrator_model=$integratorModel
        compatibility_score=$integratorScore
        compatibility_confidence=$integratorTier

        staff_tier=$commandStaffTier
        command_evidence_score=$commandEvidenceScore
        command_samples=$commandSamples
        command_assignment_score=$commandScore

        assignment_basis='COMMAND_STAFF_EVIDENCE_PLUS_COMPATIBILITY'
    }

    rookie_draft=[ordered]@{
        enabled=$true
        runtime_models_discovered=$runtimeModels.Count
        trial_assignments=@(
            $selected |
            Where-Object { $_.AssignmentType -eq 'TRIAL' } |
            ForEach-Object {
                [ordered]@{
                    role=$_.Role
                    model=$_.Model
                    confidence='UNPROVEN'
                    status='TRIAL_ASSIGNMENT'
                }
            }
        )
    }

    execution_policy=[ordered]@{
        automatic_execution=$false
        requires_go_signal=$true
        allow_runtime_backoff=$true
        allow_model_escalation=$true
        allow_toolbox_hot_swap=$true
    }

    safety=[ordered]@{
        canonical_mutation='NONE'
        vtc_execution='NONE'
        model_invocation='NONE'
        agent_execution='NONE'
    }
}

$planPath = Join-Path $formationRoot "$formationId.json"
Write-Json $planPath $plan

$latestPath = Join-Path $formationRoot 'CURRENT_FORMATION_PLAN.json'
Write-Json $latestPath $plan

$receiptPath = Join-Path $receiptRoot "AUTO_PARTY_FORMATION.$stamp.json"

Write-Json $receiptPath ([ordered]@{
    schema='vertex.world.ard.auto-party-formation-receipt.v1.2'
    completed_at=(Get-Date).ToString('o')
    mission_class=$MissionClass
    party_size=$DesiredPartySize
    physical_parallel_width=$recommendedWidth
    integrator_model=$integratorModel
    command_staff_tier=$commandStaffTier
    command_evidence_score=$commandEvidenceScore
    command_assignment_score=$commandScore
    formation_plan=$planPath
    automatic_execution=$false
    canonical_mutation='NONE'
    vtc_execution='NONE'
})

Write-Host ''
Write-Host '[AUTO PARTY]' -ForegroundColor Cyan

$position = 0
foreach ($member in ($selected | Sort-Object FormationScore -Descending)) {
    $position++

    Write-Host (
        "  {0}. {1,-14} model={2,-28} score={3} confidence={4} status={5} roster={6}" -f `
        $position,
        $member.Role,
        $member.Model,
        $member.FormationScore,
        $member.Confidence,
        $member.AssignmentStatus,
        $member.RosterState
    )
}

$rookies = @($selected | Where-Object { $_.AssignmentType -eq 'TRIAL' })

Write-Host ''
Write-Host '[ROOKIE DRAFT]' -ForegroundColor Cyan

if ($rookies.Count -eq 0) {
    Write-Host '  No trial assignments required.'
}
else {
    foreach ($r in $rookies) {
        Write-Host ("  {0,-14} -> {1}  UNPROVEN / TRIAL_ASSIGNMENT" -f $r.Role,$r.Model)
    }
}

Write-Host ''
Write-Host '[FORMATION CONTROL]' -ForegroundColor Cyan
Write-Host "  Logical Party Size : $DesiredPartySize"
Write-Host "  Physical Width     : $recommendedWidth"
Write-Host "  Formation Evidence : $formationConservative / $formationConfidenceTier"

Write-Host ''
Write-Host '[COMMAND]' -ForegroundColor Cyan
Write-Host "  Integrator         : $integratorModel"
Write-Host "  Staff Tier         : $commandStaffTier"
Write-Host "  Command Evidence   : $commandEvidenceScore"
Write-Host "  Compatibility      : $integratorScore"
Write-Host "  Compatibility Conf : $integratorTier"
Write-Host "  Command Score      : $commandScore"
Write-Host "  Samples            : $commandSamples"

Write-Host ''
Write-Host "Formation Plan : $planPath"
Write-Host "Current Plan   : $latestPath"
Write-Host "Receipt        : $receiptPath"

Write-Host ''
Write-Host 'AUTO EXECUTION      : DISABLED'
Write-Host 'GO SIGNAL REQUIRED  : YES'
Write-Host 'CANONICAL MUTATION  : NONE'
Write-Host 'VTC EXECUTION       : NONE'
Write-Host ''
Write-Host 'VERTEX WORLD — AUTO PARTY FORMATION READY.'
Write-Host '轟。' -ForegroundColor Green
