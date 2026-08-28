#requires -Version 7.0
<#
VERTEX WORLD — COMMAND STAFF EVIDENCE ENGINE V0.1.0

PURPOSE
  Build command-staff-specific evidence from real ARD/VXN RPG battle logs.

COMMAND STAFF EVIDENCE AXES
  - Integration Success Rate
  - Mission Clear Contribution
  - Escalation Avoidance
  - Integrator Compatibility
  - Evidence Confidence
  - Samples

STAFF TIERS
  - PROBATIONARY_STAFF
  - ACTIVE_STAFF
  - SENIOR_STAFF
  - COMMANDER_CLASS

SAFETY
  - Reads RPG battle logs / affinity confidence.
  - Writes only under VXN\runtime\rpg.
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
$confidencePath = Join-Path $rpgRoot 'confidence\VERTEX_WORLD_AFFINITY_CONFIDENCE.json'

$staffRoot = Join-Path $rpgRoot 'command_staff'
$historyRoot = Join-Path $staffRoot 'history'
$receiptRoot = Join-Path $rpgRoot 'receipts'

@($staffRoot,$historyRoot,$receiptRoot) | ForEach-Object {
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

function Clamp01([double]$Value) {
    return [math]::Max(0.0,[math]::Min(1.0,$Value))
}

function Get-ConfidenceTier([int]$Samples) {
    if ($Samples -ge 50) { return 'ESTABLISHED' }
    if ($Samples -ge 20) { return 'TRUSTED' }
    if ($Samples -ge 5)  { return 'EMERGING' }
    return 'PROVISIONAL'
}

function Get-ConfidenceIndex([int]$Samples) {
    if ($Samples -le 0) { return 0 }

    $value = 100.0 * (1.0 - [math]::Exp(-1.0 * $Samples / 12.0))
    return [int][math]::Round([math]::Min(100.0,$value))
}

function Get-StaffTier {
    param(
        [int]$Samples,
        [double]$EvidenceScore,
        [double]$IntegrationRate,
        [double]$MissionClearRate
    )

    if (
        $Samples -ge 50 -and
        $EvidenceScore -ge 90 -and
        $IntegrationRate -ge 0.95 -and
        $MissionClearRate -ge 0.95
    ) {
        return 'COMMANDER_CLASS'
    }

    if (
        $Samples -ge 20 -and
        $EvidenceScore -ge 82 -and
        $IntegrationRate -ge 0.90 -and
        $MissionClearRate -ge 0.90
    ) {
        return 'SENIOR_STAFF'
    }

    if (
        $Samples -ge 2 -and
        $EvidenceScore -ge 65 -and
        $IntegrationRate -ge 0.75
    ) {
        return 'ACTIVE_STAFF'
    }

    return 'PROBATIONARY_STAFF'
}

function Get-CompatibilityEvidence {
    param(
        $ConfidenceIndex,
        [string]$PartyModel,
        [string]$IntegratorModel
    )

    $entries = @(
        Get-Prop $ConfidenceIndex 'integrator_compatibility' @()
    )

    $entry = $entries |
        Where-Object {
            [string](Get-Prop $_ 'party_model' '') -eq $PartyModel -and
            [string](Get-Prop $_ 'integrator_model' '') -eq $IntegratorModel
        } |
        Select-Object -First 1

    if ($null -eq $entry) {
        return [pscustomobject]@{
            Conservative=50.0
            Tier='PROVISIONAL'
            Samples=0
        }
    }

    $confidence = Get-Prop $entry 'confidence' $null

    return [pscustomobject]@{
        Conservative=[double](Get-Prop $confidence 'conservative_score' 50)
        Tier=[string](Get-Prop $confidence 'confidence_tier' 'PROVISIONAL')
        Samples=[int](Get-Prop $entry 'samples' 0)
    }
}

Banner 'VERTEX WORLD — COMMAND STAFF EVIDENCE ENGINE V0.1.0'

if (-not (Test-Path -LiteralPath $battleRoot)) {
    throw "Battle log directory not found: $battleRoot"
}

$battleFiles = @(
    Get-ChildItem -LiteralPath $battleRoot -File -Filter '*.RPG_BATTLE_LOG.json' |
    Sort-Object LastWriteTime
)

if ($battleFiles.Count -eq 0) {
    throw 'No RPG battle logs found.'
}

$confidenceIndex = Read-JsonSafe $confidencePath

Write-Host "Battle Logs : $($battleFiles.Count)"

$staffStats = @{}

foreach ($file in $battleFiles) {
    $battle = Read-JsonSafe $file.FullName
    if ($null -eq $battle) { continue }

    $party = Get-Prop $battle 'party' $null
    $partyModel = [string](Get-Prop $party 'model' '')

    $command = Get-Prop $battle 'command' $null
    $integratorModel = [string](Get-Prop $command 'integrator' '')
    $integratorGreen = [bool](Get-Prop $command 'integrator_green' $false)
    $escalationUsed = [bool](Get-Prop $command 'escalation_used' $false)

    $missionResult = [string](Get-Prop $battle 'mission_result' 'MISSION_HOLD')
    $missionClear = ($missionResult -eq 'MISSION_CLEAR')

    if (-not [string]::IsNullOrWhiteSpace($integratorModel)) {
        $key = "INTEGRATOR::$integratorModel"

        if (-not $staffStats.ContainsKey($key)) {
            $staffStats[$key] = [ordered]@{
                staff_id=$key
                role='Integrator'
                staff_class='INTEGRATOR'
                model=$integratorModel

                samples=0
                integration_green=0
                mission_clears=0
                escalation_avoided=0
                total_final_score=0.0

                party_models=@{}
            }
        }

        $s = $staffStats[$key]

        $s.samples++

        if ($integratorGreen) {
            $s.integration_green++
        }

        if ($missionClear) {
            $s.mission_clears++
        }

        if (-not $escalationUsed) {
            $s.escalation_avoided++
        }

        $s.total_final_score += [double](Get-Prop $battle 'final_score' 0)

        if (-not $s.party_models.ContainsKey($partyModel)) {
            $s.party_models[$partyModel] = 0
        }

        $s.party_models[$partyModel]++
    }

    if ($escalationUsed) {
        $finalModel = [string](Get-Prop $command 'final_model' '')

        if (-not [string]::IsNullOrWhiteSpace($finalModel) -and $finalModel -ne $integratorModel) {
            $key = "REVIEWER::$finalModel"

            if (-not $staffStats.ContainsKey($key)) {
                $staffStats[$key] = [ordered]@{
                    staff_id=$key
                    role='Senior Reviewer'
                    staff_class='REVIEWER'
                    model=$finalModel

                    samples=0
                    integration_green=0
                    mission_clears=0
                    escalation_avoided=0
                    total_final_score=0.0

                    party_models=@{}
                }
            }

            $s = $staffStats[$key]
            $s.samples++

            if ($missionClear) {
                $s.mission_clears++
                $s.integration_green++
            }

            $s.total_final_score += [double](Get-Prop $battle 'final_score' 0)

            if (-not $s.party_models.ContainsKey($partyModel)) {
                $s.party_models[$partyModel] = 0
            }

            $s.party_models[$partyModel]++
        }
    }
}

$staffProfiles = @()

foreach ($key in $staffStats.Keys) {
    $s = $staffStats[$key]

    $samples = [int]$s.samples

    $integrationRate = if ($samples -gt 0) {
        $s.integration_green / [double]$samples
    } else {
        0.0
    }

    $clearRate = if ($samples -gt 0) {
        $s.mission_clears / [double]$samples
    } else {
        0.0
    }

    $avoidRate = if ($samples -gt 0) {
        $s.escalation_avoided / [double]$samples
    } else {
        0.0
    }

    $avgScore = if ($samples -gt 0) {
        $s.total_final_score / [double]$samples
    } else {
        0.0
    }

    $compatScores = @()

    foreach ($partyModel in $s.party_models.Keys) {
        if ($null -ne $confidenceIndex -and $s.staff_class -eq 'INTEGRATOR') {
            $evidence = Get-CompatibilityEvidence `
                -ConfidenceIndex $confidenceIndex `
                -PartyModel $partyModel `
                -IntegratorModel $s.model

            $compatScores += [double]$evidence.Conservative
        }
    }

    $compatibility = if ($compatScores.Count -gt 0) {
        ($compatScores | Measure-Object -Average).Average
    } else {
        50.0
    }

    $evidenceScore = (
        ((Clamp01 $integrationRate) * 0.30) +
        ((Clamp01 $clearRate) * 0.25) +
        ((Clamp01 $avoidRate) * 0.20) +
        ((Clamp01 $avgScore) * 0.10) +
        (($compatibility / 100.0) * 0.15)
    ) * 100.0

    $evidenceScore = [math]::Round($evidenceScore,1)

    $confidenceTier = Get-ConfidenceTier $samples
    $confidenceIndexValue = Get-ConfidenceIndex $samples

    $staffTier = Get-StaffTier `
        -Samples $samples `
        -EvidenceScore $evidenceScore `
        -IntegrationRate $integrationRate `
        -MissionClearRate $clearRate

    $staffProfiles += [ordered]@{
        staff_id=$s.staff_id
        role=$s.role
        staff_class=$s.staff_class
        model=$s.model

        staff_tier=$staffTier

        evidence=[ordered]@{
            samples=$samples
            integration_success_rate=[math]::Round($integrationRate,3)
            mission_clear_contribution=[math]::Round($clearRate,3)
            escalation_avoidance_rate=[math]::Round($avoidRate,3)
            average_final_score=[math]::Round($avgScore,3)
            compatibility_score=[math]::Round($compatibility,1)
            evidence_score=$evidenceScore
        }

        confidence=[ordered]@{
            tier=$confidenceTier
            index=$confidenceIndexValue
        }

        party_models=@(
            $s.party_models.Keys |
            ForEach-Object {
                [ordered]@{
                    model=$_
                    samples=$s.party_models[$_]
                }
            }
        )
    }
}

$staffProfiles = @(
    $staffProfiles |
    Sort-Object {
        [double](Get-Prop (Get-Prop $_ 'evidence' $null) 'evidence_score' 0)
    } -Descending
)

$currentPath = Join-Path $staffRoot 'CURRENT_COMMAND_STAFF.json'

$output = [ordered]@{
    schema='vertex.world.rpg.command-staff-evidence.v1'
    updated_at=(Get-Date).ToString('o')

    counts=[ordered]@{
        total=$staffProfiles.Count
        commander_class=@($staffProfiles | Where-Object { $_.staff_tier -eq 'COMMANDER_CLASS' }).Count
        senior_staff=@($staffProfiles | Where-Object { $_.staff_tier -eq 'SENIOR_STAFF' }).Count
        active_staff=@($staffProfiles | Where-Object { $_.staff_tier -eq 'ACTIVE_STAFF' }).Count
        probationary_staff=@($staffProfiles | Where-Object { $_.staff_tier -eq 'PROBATIONARY_STAFF' }).Count
    }

    staff=$staffProfiles

    policy=[ordered]@{
        field_role_affinity_not_used_for_command_staff=$true
        integration_evidence_primary=$true
        low_sample_results_are_provisional=$true
    }
}

Write-Json $currentPath $output

$historyPath = Join-Path $historyRoot "COMMAND_STAFF.$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"
Write-Json $historyPath $output

$receiptPath = Join-Path $receiptRoot "COMMAND_STAFF_EVIDENCE.$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"

Write-Json $receiptPath ([ordered]@{
    schema='vertex.world.rpg.command-staff-evidence-receipt.v1'
    completed_at=(Get-Date).ToString('o')
    battle_logs_processed=$battleFiles.Count
    staff_count=$staffProfiles.Count
    output=$currentPath
    canonical_mutation='NONE'
    vtc_execution='NONE'
    model_invocation='NONE'
    agent_execution='NONE'
})

Write-Host ''
Write-Host '[COMMAND STAFF]' -ForegroundColor Cyan

foreach ($s in $staffProfiles) {
    Write-Host (
        "  {0,-18} {1,-20} model={2}" -f `
        $s.role,
        $s.staff_tier,
        $s.model
    )

    Write-Host (
        "      evidence={0} samples={1} integration={2} clear={3} avoidEsc={4} compat={5} confidence={6}" -f `
        $s.evidence.evidence_score,
        $s.evidence.samples,
        $s.evidence.integration_success_rate,
        $s.evidence.mission_clear_contribution,
        $s.evidence.escalation_avoidance_rate,
        $s.evidence.compatibility_score,
        $s.confidence.tier
    )
}

Write-Host ''
Write-Host '[STAFF COUNTS]' -ForegroundColor Cyan
Write-Host "  Commander Class : $($output.counts.commander_class)"
Write-Host "  Senior Staff    : $($output.counts.senior_staff)"
Write-Host "  Active Staff    : $($output.counts.active_staff)"
Write-Host "  Probationary    : $($output.counts.probationary_staff)"

Write-Host ''
Write-Host "Current Staff : $currentPath"
Write-Host "History       : $historyPath"
Write-Host "Receipt       : $receiptPath"

Write-Host ''
Write-Host 'COMMAND STAFF IS NOW EVALUATED ON COMMAND EVIDENCE.'
Write-Host 'CANONICAL MUTATION : NONE'
Write-Host 'VTC EXECUTION      : NONE'
Write-Host 'MODEL INVOCATION   : NONE'
Write-Host 'AGENT EXECUTION    : NONE'
Write-Host ''
Write-Host 'VERTEX WORLD — COMMAND STAFF ONLINE.'
Write-Host '轟。' -ForegroundColor Green
