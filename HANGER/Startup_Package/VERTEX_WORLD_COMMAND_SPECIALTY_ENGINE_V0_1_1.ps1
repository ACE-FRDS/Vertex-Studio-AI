#requires -Version 7.0
<#
VERTEX WORLD — COMMAND SPECIALTY ENGINE V0.1.1

PURPOSE
  Build mission-class-specific command affinity from real RPG battle logs.

MISSION CLASSES
  - GENERAL
  - CODING
  - MEMORY_RECALL
  - TRANSACTION_SAFETY
  - UI_LOCK_SCOPE
  - REVIEW

EVIDENCE AXES PER COMMAND STAFF / MISSION CLASS
  - Samples
  - Integration success
  - Mission clear contribution
  - Escalation avoidance
  - Average final score
  - Compatibility
  - Confidence
  - Specialty score

SAFETY
  - No model invocation.
  - No agent execution.
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
$commandStaffPath = Join-Path $rpgRoot 'command_staff\CURRENT_COMMAND_STAFF.json'
$confidencePath = Join-Path $rpgRoot 'confidence\VERTEX_WORLD_AFFINITY_CONFIDENCE.json'

$specialtyRoot = Join-Path $rpgRoot 'command_specialty'
$historyRoot = Join-Path $specialtyRoot 'history'
$receiptRoot = Join-Path $rpgRoot 'receipts'

@($specialtyRoot,$historyRoot,$receiptRoot) | ForEach-Object {
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

    if ($null -eq $Object) {
        return $Default
    }

    # Hashtable / OrderedDictionary / IDictionary support.
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }

        try {
            if ($Object.ContainsKey($Name)) {
                return $Object[$Name]
            }
        }
        catch {}

        return $Default
    }

    # PSCustomObject / ordinary object support.
    $p = $Object.PSObject.Properties[$Name]

    if ($null -eq $p -or $null -eq $p.Value) {
        return $Default
    }

    return $p.Value
}

function Clamp01([double]$Value) {
    return [math]::Max(0.0,[math]::Min(1.0,$Value))
}

function Get-ConfidenceTier([int]$Samples) {
    if ($Samples -ge 50) { return 'ESTABLISHED' }
    if ($Samples -ge 20) { return 'TRUSTED' }
    if ($Samples -ge 5)  { return 'EMERGING' }
    return 'PROVISIONAL'
}

function Get-ConservativeSpecialty {
    param(
        [double]$RawScore,
        [int]$Samples,
        [double]$Prior=50.0,
        [double]$PriorWeight=4.0
    )

    $v = (
        ($RawScore * $Samples) +
        ($Prior * $PriorWeight)
    ) / ($Samples + $PriorWeight)

    return [math]::Round($v,1)
}

function Get-CompatibilityForModel {
    param(
        $ConfidenceIndex,
        [string]$IntegratorModel
    )

    if ($null -eq $ConfidenceIndex) {
        return 50.0
    }

    $entries = @(
        Get-Prop $ConfidenceIndex 'integrator_compatibility' @()
    )

    $matches = @(
        $entries |
        Where-Object {
            [string](Get-Prop $_ 'integrator_model' '') -eq $IntegratorModel
        }
    )

    if ($matches.Count -eq 0) {
        return 50.0
    }

    $scores = @()

    foreach ($m in $matches) {
        $c = Get-Prop $m 'confidence' $null
        $scores += [double](Get-Prop $c 'conservative_score' 50)
    }

    return [math]::Round(
        ($scores | Measure-Object -Average).Average,
        1
    )
}

Banner 'VERTEX WORLD — COMMAND SPECIALTY ENGINE V0.1.1'

if (-not (Test-Path -LiteralPath $battleRoot)) {
    throw "Battle logs not found: $battleRoot"
}

$battleFiles = @(
    Get-ChildItem -LiteralPath $battleRoot -File -Filter '*.RPG_BATTLE_LOG.json' |
    Sort-Object LastWriteTime
)

if ($battleFiles.Count -eq 0) {
    throw 'No RPG battle logs found.'
}

$commandStaff = Read-JsonSafe $commandStaffPath
$confidenceIndex = Read-JsonSafe $confidencePath

$knownStaff = @()

if ($null -ne $commandStaff) {
    $knownStaff = @(Get-Prop $commandStaff 'staff' @())
}

Write-Host "Battle Logs : $($battleFiles.Count)"
Write-Host "Known Staff : $($knownStaff.Count)"

$stats = @{}

foreach ($file in $battleFiles) {
    $battle = Read-JsonSafe $file.FullName
    if ($null -eq $battle) { continue }

    $missionClass = [string](Get-Prop $battle 'mission_class' 'GENERAL')
    if ([string]::IsNullOrWhiteSpace($missionClass)) {
        $missionClass = 'GENERAL'
    }

    $command = Get-Prop $battle 'command' $null
    $integratorModel = [string](Get-Prop $command 'integrator' '')
    $integratorGreen = [bool](Get-Prop $command 'integrator_green' $false)
    $escalationUsed = [bool](Get-Prop $command 'escalation_used' $false)

    $missionResult = [string](Get-Prop $battle 'mission_result' 'MISSION_HOLD')
    $missionClear = ($missionResult -eq 'MISSION_CLEAR')
    $finalScore = [double](Get-Prop $battle 'final_score' 0)

    if (-not [string]::IsNullOrWhiteSpace($integratorModel)) {
        $key = "$integratorModel::$missionClass"

        if (-not $stats.ContainsKey($key)) {
            $stats[$key] = [ordered]@{
                model=$integratorModel
                mission_class=$missionClass
                samples=0
                integration_green=0
                mission_clears=0
                escalation_avoided=0
                total_score=0.0
            }
        }

        $s = $stats[$key]
        $s.samples++

        if ($integratorGreen) { $s.integration_green++ }
        if ($missionClear) { $s.mission_clears++ }
        if (-not $escalationUsed) { $s.escalation_avoided++ }

        $s.total_score += $finalScore
    }
}

$profiles = @()

foreach ($key in $stats.Keys) {
    $s = $stats[$key]

    $samples = [int]$s.samples

    $integrationRate = if ($samples -gt 0) {
        $s.integration_green / [double]$samples
    } else { 0.0 }

    $clearRate = if ($samples -gt 0) {
        $s.mission_clears / [double]$samples
    } else { 0.0 }

    $avoidRate = if ($samples -gt 0) {
        $s.escalation_avoided / [double]$samples
    } else { 0.0 }

    $avgScore = if ($samples -gt 0) {
        $s.total_score / [double]$samples
    } else { 0.0 }

    $compatibility = Get-CompatibilityForModel `
        -ConfidenceIndex $confidenceIndex `
        -IntegratorModel $s.model

    $rawScore = (
        ((Clamp01 $integrationRate) * 0.30) +
        ((Clamp01 $clearRate) * 0.25) +
        ((Clamp01 $avoidRate) * 0.20) +
        ((Clamp01 $avgScore) * 0.10) +
        (($compatibility / 100.0) * 0.15)
    ) * 100.0

    $rawScore = [math]::Round($rawScore,1)

    $conservative = Get-ConservativeSpecialty `
        -RawScore $rawScore `
        -Samples $samples

    $tier = Get-ConfidenceTier $samples

    $profiles += [ordered]@{
        model=$s.model
        mission_class=$s.mission_class

        specialty=[ordered]@{
            raw_score=$rawScore
            conservative_score=$conservative
        }

        evidence=[ordered]@{
            samples=$samples
            integration_success_rate=[math]::Round($integrationRate,3)
            mission_clear_rate=[math]::Round($clearRate,3)
            escalation_avoidance_rate=[math]::Round($avoidRate,3)
            average_final_score=[math]::Round($avgScore,3)
            compatibility_score=$compatibility
        }

        confidence=[ordered]@{
            tier=$tier
        }
    }
}

$profiles = @(
    $profiles |
    Sort-Object {
        [double](Get-Prop (Get-Prop $_ 'specialty' $null) 'conservative_score' 0)
    } -Descending
)

$byMission = @{}

foreach ($p in $profiles) {
    $missionClass = [string]$p.mission_class

    if (-not $byMission.ContainsKey($missionClass)) {
        $byMission[$missionClass] = @()
    }

    $byMission[$missionClass] += $p
}

$missionIndex = @()

foreach ($missionClass in ($byMission.Keys | Sort-Object)) {
    $entries = @(
        $byMission[$missionClass] |
        Sort-Object {
            [double](Get-Prop (Get-Prop $_ 'specialty' $null) 'conservative_score' 0)
        } -Descending
    )

    $best = $entries | Select-Object -First 1

    $bestModel = [string](Get-Prop $best 'model' '')
    $bestSpecialty = Get-Prop $best 'specialty' $null
    $bestConfidence = Get-Prop $best 'confidence' $null

    $missionIndex += [ordered]@{
        mission_class=$missionClass
        best_command_model=$bestModel
        best_specialty_score=[double](Get-Prop $bestSpecialty 'conservative_score' 0)
        confidence=[string](Get-Prop $bestConfidence 'tier' 'PROVISIONAL')
        candidates=$entries
    }
}

$output = [ordered]@{
    schema='vertex.world.rpg.command-specialty.v1.1'
    updated_at=(Get-Date).ToString('o')
    battle_logs_processed=$battleFiles.Count
    profiles=$profiles
    mission_index=$missionIndex
    policy=[ordered]@{
        specialty_is_mission_class_specific=$true
        low_sample_results_are_shrunk_toward_neutral=$true
        command_staff_general_score_remains_separate=$true
    }
}

$currentPath = Join-Path $specialtyRoot 'CURRENT_COMMAND_SPECIALTY.json'
Write-Json $currentPath $output

$historyPath = Join-Path $historyRoot "COMMAND_SPECIALTY.$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"
Write-Json $historyPath $output

$receiptPath = Join-Path $receiptRoot "COMMAND_SPECIALTY.$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"

Write-Json $receiptPath ([ordered]@{
    schema='vertex.world.rpg.command-specialty-receipt.v1.1'
    completed_at=(Get-Date).ToString('o')
    battle_logs_processed=$battleFiles.Count
    profiles=$profiles.Count
    output=$currentPath
    canonical_mutation='NONE'
    vtc_execution='NONE'
    model_invocation='NONE'
    agent_execution='NONE'
})

Write-Host ''
Write-Host '[COMMAND SPECIALTY]' -ForegroundColor Cyan

foreach ($m in $missionIndex) {
    Write-Host (
        "  {0,-24} model={1} specialty={2} confidence={3}" -f `
        $m.mission_class,
        $m.best_command_model,
        $m.best_specialty_score,
        $m.confidence
    )
}

Write-Host ''
Write-Host '[DETAIL]' -ForegroundColor Cyan

foreach ($p in $profiles) {
    Write-Host (
        "  {0} / {1}" -f `
        $p.model,
        $p.mission_class
    )

    Write-Host (
        "      raw={0} conservative={1} samples={2} integration={3} clear={4} avoidEsc={5}" -f `
        $p.specialty.raw_score,
        $p.specialty.conservative_score,
        $p.evidence.samples,
        $p.evidence.integration_success_rate,
        $p.evidence.mission_clear_rate,
        $p.evidence.escalation_avoidance_rate
    )
}

Write-Host ''
Write-Host "Current Specialty : $currentPath"
Write-Host "History           : $historyPath"
Write-Host "Receipt           : $receiptPath"

Write-Host ''
Write-Host 'COMMAND SPECIALTY IS NOW MISSION-CLASS SPECIFIC.'
Write-Host 'CANONICAL MUTATION : NONE'
Write-Host 'VTC EXECUTION      : NONE'
Write-Host 'MODEL INVOCATION   : NONE'
Write-Host 'AGENT EXECUTION    : NONE'
Write-Host ''
Write-Host 'VERTEX WORLD — COMMAND SPECIALTY ONLINE.'
Write-Host '轟。' -ForegroundColor Green
