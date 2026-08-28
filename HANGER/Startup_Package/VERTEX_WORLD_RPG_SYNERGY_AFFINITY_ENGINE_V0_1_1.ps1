#requires -Version 7.0
<#
VERTEX WORLD — RPG SYNERGY & AFFINITY ENGINE V0.1.1

PURPOSE
  Derive RPG-facing synergy and affinity from real ARD/VXN telemetry.

DERIVED SYSTEMS
  - Role Affinity
  - Party Synergy
  - Model-to-Role Affinity
  - Equipment Affinity
  - Formation Affinity
  - Integrator Compatibility
  - Escalation Dependency

NO FAKE STATS
  All scores are normalized presentation indices derived from real execution evidence.

SAFETY
  - Reads runtime RPG/ARD/VXN telemetry only.
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
$characterRoot = Join-Path $rpgRoot 'characters'
$partyRoot = Join-Path $rpgRoot 'parties'
$synergyRoot = Join-Path $rpgRoot 'synergy'
$affinityRoot = Join-Path $rpgRoot 'affinity'
$receiptRoot = Join-Path $rpgRoot 'receipts'

@($synergyRoot,$affinityRoot,$receiptRoot) | ForEach-Object {
    $null = New-Item -ItemType Directory -Force -Path $_
}

function Banner([string]$Text) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Magenta
    Write-Host " $Text" -ForegroundColor Magenta
    Write-Host '============================================================' -ForegroundColor Magenta
}

function Write-Json([string]$Path, $Object) {
    $parent = Split-Path -Parent $Path
    if ($parent) { $null = New-Item -ItemType Directory -Force -Path $parent }
    $Object | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
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

function Clamp01([double]$v) {
    return [math]::Max(0.0,[math]::Min(1.0,$v))
}

function ToIndex100([double]$v) {
    return [int][math]::Round((Clamp01 $v) * 100.0)
}

function Get-PairKey([string]$A,[string]$B) {
    $arr = @($A,$B) | Sort-Object
    return "$($arr[0])::$($arr[1])"
}

function Get-ToolIdsFromBattle($Battle) {
    $tools = New-Object System.Collections.Generic.HashSet[string]

    $events = @(Get-Prop $Battle 'events' @())
    foreach ($e in $events) {
        $msg = [string](Get-Prop $e 'rpg_message' '')
        foreach ($candidate in @('LOCK_SCOPE','VCC_VSP','CANDIDATE_VTC','IMPACT_ASSOCIATION')) {
            if ($msg -match [regex]::Escape($candidate)) {
                $null = $tools.Add($candidate)
            }
        }
    }

    $source = [string](Get-Prop $Battle 'source_receipt' '')
    if (-not [string]::IsNullOrWhiteSpace($source) -and (Test-Path -LiteralPath $source)) {
        $receipt = Read-JsonSafe $source
        if ($null -ne $receipt) {
            $final = Get-Prop $receipt 'final' $null
            $result = Get-Prop $final 'result' $null

            if ($null -ne $result) {
                $toolbox = @(Get-Prop $result 'toolbox' @())
                foreach ($t in $toolbox) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$t)) {
                        $null = $tools.Add([string]$t)
                    }
                }
            }
        }
    }

    return @($tools)
}

Banner 'VERTEX WORLD — RPG SYNERGY & AFFINITY ENGINE V0.1.1'

$battleFiles = @()
if (Test-Path -LiteralPath $battleRoot) {
    $battleFiles = @(
        Get-ChildItem -LiteralPath $battleRoot -Filter '*.RPG_BATTLE_LOG.json' -File |
        Sort-Object LastWriteTime
    )
}

if ($battleFiles.Count -eq 0) {
    throw 'No RPG battle logs found.'
}

Write-Host "Battle Logs : $($battleFiles.Count)"

$roleStats = @{}
$pairStats = @{}
$equipmentStats = @{}
$formationStats = @{}
$integratorStats = @{}
$modelRoleStats = @{}

foreach ($file in $battleFiles) {
    $battle = Read-JsonSafe $file.FullName
    if ($null -eq $battle) { continue }

    $clear = ([string](Get-Prop $battle 'mission_result' 'MISSION_HOLD') -eq 'MISSION_CLEAR')
    $finalScore = [double](Get-Prop $battle 'final_score' 0)

    $party = Get-Prop $battle 'party' $null
    $partyModel = [string](Get-Prop $party 'model' '')
    $logicalSize = [int](Get-Prop $party 'logical_size' 0)
    $stableWidth = [int](Get-Prop $party 'stable_physical_width' 0)
    $characters = @(Get-Prop $party 'characters' @())

    $command = Get-Prop $battle 'command' $null
    $integratorModel = [string](Get-Prop $command 'integrator' '')
    $integratorGreen = [bool](Get-Prop $command 'integrator_green' $false)
    $escalationUsed = [bool](Get-Prop $command 'escalation_used' $false)

    $tools = @(Get-ToolIdsFromBattle $battle)

    # Role/model-role stats
    foreach ($c in $characters) {
        $name = [string](Get-Prop $c 'display_name' 'Agent')
        $class = [string](Get-Prop $c 'class' 'AGENT')
        $status = [string](Get-Prop $c 'status' 'READY')
        $success = ($status -eq 'READY')

        $stats = Get-Prop $c 'measured_stats' $null
        $latency = [double](Get-Prop $stats 'latency_ms' 0)

        if (-not $roleStats.ContainsKey($name)) {
            $roleStats[$name] = [ordered]@{
                role=$name
                class=$class
                samples=0
                successes=0
                clears=0
                total_latency_ms=0.0
                total_score=0.0
            }
        }

        $r = $roleStats[$name]
        $r.samples++
        if ($success) { $r.successes++ }
        if ($clear) { $r.clears++ }
        $r.total_latency_ms += $latency
        $r.total_score += $finalScore

        $mrKey = "$partyModel::$name"
        if (-not $modelRoleStats.ContainsKey($mrKey)) {
            $modelRoleStats[$mrKey] = [ordered]@{
                model=$partyModel
                role=$name
                samples=0
                successes=0
                clears=0
                total_latency_ms=0.0
            }
        }

        $mr = $modelRoleStats[$mrKey]
        $mr.samples++
        if ($success) { $mr.successes++ }
        if ($clear) { $mr.clears++ }
        $mr.total_latency_ms += $latency
    }

    # Pair synergy
    for ($i=0; $i -lt $characters.Count; $i++) {
        for ($j=$i+1; $j -lt $characters.Count; $j++) {
            $a = [string](Get-Prop $characters[$i] 'display_name' 'Agent')
            $b = [string](Get-Prop $characters[$j] 'display_name' 'Agent')
            $key = Get-PairKey $a $b

            if (-not $pairStats.ContainsKey($key)) {
                $pairStats[$key] = [ordered]@{
                    pair=$key
                    role_a=($key -split '::')[0]
                    role_b=($key -split '::')[1]
                    samples=0
                    clears=0
                    total_score=0.0
                    escalation_count=0
                }
            }

            $p = $pairStats[$key]
            $p.samples++
            if ($clear) { $p.clears++ }
            $p.total_score += $finalScore
            if ($escalationUsed) { $p.escalation_count++ }
        }
    }

    # Equipment affinity
    foreach ($tool in $tools) {
        $key = "$partyModel::$tool"

        if (-not $equipmentStats.ContainsKey($key)) {
            $equipmentStats[$key] = [ordered]@{
                model=$partyModel
                tool=$tool
                samples=0
                clears=0
                total_score=0.0
                escalation_count=0
            }
        }

        $e = $equipmentStats[$key]
        $e.samples++
        if ($clear) { $e.clears++ }
        $e.total_score += $finalScore
        if ($escalationUsed) { $e.escalation_count++ }
    }

    # Formation affinity
    $formationKey = "$partyModel::party$logicalSize::width$stableWidth"
    if (-not $formationStats.ContainsKey($formationKey)) {
        $formationStats[$formationKey] = [ordered]@{
            formation=$formationKey
            model=$partyModel
            logical_party_size=$logicalSize
            stable_width=$stableWidth
            samples=0
            clears=0
            total_score=0.0
            escalation_count=0
        }
    }

    $f = $formationStats[$formationKey]
    $f.samples++
    if ($clear) { $f.clears++ }
    $f.total_score += $finalScore
    if ($escalationUsed) { $f.escalation_count++ }

    # Integrator compatibility
    if (-not [string]::IsNullOrWhiteSpace($integratorModel)) {
        $key = "$partyModel::$integratorModel"

        if (-not $integratorStats.ContainsKey($key)) {
            $integratorStats[$key] = [ordered]@{
                party_model=$partyModel
                integrator_model=$integratorModel
                samples=0
                integration_green=0
                mission_clears=0
                escalation_count=0
                total_score=0.0
            }
        }

        $x = $integratorStats[$key]
        $x.samples++
        if ($integratorGreen) { $x.integration_green++ }
        if ($clear) { $x.mission_clears++ }
        if ($escalationUsed) { $x.escalation_count++ }
        $x.total_score += $finalScore
    }
}

# Finalize normalized indices
$roleAffinity = @()
foreach ($key in $roleStats.Keys) {
    $r = $roleStats[$key]
    $samples = [double]$r.samples
    $successRate = if ($samples -gt 0) { $r.successes / $samples } else { 0.0 }
    $clearRate = if ($samples -gt 0) { $r.clears / $samples } else { 0.0 }
    $avgScore = if ($samples -gt 0) { $r.total_score / $samples } else { 0.0 }
    $avgLatency = if ($samples -gt 0) { $r.total_latency_ms / $samples } else { 0.0 }

    $latencyScore = if ($avgLatency -le 0) { 0.5 }
        elseif ($avgLatency -lt 7000) { 1.0 }
        elseif ($avgLatency -lt 12000) { 0.85 }
        elseif ($avgLatency -lt 20000) { 0.70 }
        else { 0.50 }

    $affinity = (
        $successRate * 0.35 +
        $clearRate * 0.30 +
        (Clamp01 $avgScore) * 0.20 +
        $latencyScore * 0.15
    )

    $roleAffinity += [ordered]@{
        role=$r.role
        class=$r.class
        samples=$r.samples
        success_rate=[math]::Round($successRate,3)
        clear_rate=[math]::Round($clearRate,3)
        average_score=[math]::Round($avgScore,3)
        average_latency_ms=[math]::Round($avgLatency,1)
        affinity_index=(ToIndex100 $affinity)
    }
}

$pairSynergy = @()
foreach ($key in $pairStats.Keys) {
    $p = $pairStats[$key]
    $samples = [double]$p.samples
    $clearRate = if ($samples -gt 0) { $p.clears / $samples } else { 0.0 }
    $avgScore = if ($samples -gt 0) { $p.total_score / $samples } else { 0.0 }
    $escalationRate = if ($samples -gt 0) { $p.escalation_count / $samples } else { 0.0 }

    $score = (
        $clearRate * 0.45 +
        (Clamp01 $avgScore) * 0.35 +
        (1.0 - (Clamp01 $escalationRate)) * 0.20
    )

    $pairSynergy += [ordered]@{
        role_a=$p.role_a
        role_b=$p.role_b
        samples=$p.samples
        clear_rate=[math]::Round($clearRate,3)
        average_score=[math]::Round($avgScore,3)
        escalation_rate=[math]::Round($escalationRate,3)
        synergy_index=(ToIndex100 $score)
    }
}

$modelRoleAffinity = @()
foreach ($key in $modelRoleStats.Keys) {
    $m = $modelRoleStats[$key]
    $samples = [double]$m.samples
    $successRate = if ($samples -gt 0) { $m.successes / $samples } else { 0.0 }
    $clearRate = if ($samples -gt 0) { $m.clears / $samples } else { 0.0 }
    $avgLatency = if ($samples -gt 0) { $m.total_latency_ms / $samples } else { 0.0 }

    $latencyScore = if ($avgLatency -le 0) { 0.5 }
        elseif ($avgLatency -lt 7000) { 1.0 }
        elseif ($avgLatency -lt 12000) { 0.85 }
        elseif ($avgLatency -lt 20000) { 0.70 }
        else { 0.50 }

    $score = (
        $successRate * 0.45 +
        $clearRate * 0.35 +
        $latencyScore * 0.20
    )

    $modelRoleAffinity += [ordered]@{
        model=$m.model
        role=$m.role
        samples=$m.samples
        success_rate=[math]::Round($successRate,3)
        clear_rate=[math]::Round($clearRate,3)
        average_latency_ms=[math]::Round($avgLatency,1)
        affinity_index=(ToIndex100 $score)
    }
}

$equipmentAffinity = @()
foreach ($key in $equipmentStats.Keys) {
    $e = $equipmentStats[$key]
    $samples = [double]$e.samples
    $clearRate = if ($samples -gt 0) { $e.clears / $samples } else { 0.0 }
    $avgScore = if ($samples -gt 0) { $e.total_score / $samples } else { 0.0 }
    $escalationRate = if ($samples -gt 0) { $e.escalation_count / $samples } else { 0.0 }

    $score = (
        $clearRate * 0.50 +
        (Clamp01 $avgScore) * 0.30 +
        (1.0 - (Clamp01 $escalationRate)) * 0.20
    )

    $equipmentAffinity += [ordered]@{
        model=$e.model
        tool=$e.tool
        samples=$e.samples
        clear_rate=[math]::Round($clearRate,3)
        average_score=[math]::Round($avgScore,3)
        escalation_rate=[math]::Round($escalationRate,3)
        affinity_index=(ToIndex100 $score)
    }
}

$formationAffinity = @()
foreach ($key in $formationStats.Keys) {
    $f = $formationStats[$key]
    $samples = [double]$f.samples
    $clearRate = if ($samples -gt 0) { $f.clears / $samples } else { 0.0 }
    $avgScore = if ($samples -gt 0) { $f.total_score / $samples } else { 0.0 }
    $escalationRate = if ($samples -gt 0) { $f.escalation_count / $samples } else { 0.0 }

    $score = (
        $clearRate * 0.45 +
        (Clamp01 $avgScore) * 0.35 +
        (1.0 - (Clamp01 $escalationRate)) * 0.20
    )

    $formationAffinity += [ordered]@{
        model=$f.model
        logical_party_size=$f.logical_party_size
        stable_width=$f.stable_width
        samples=$f.samples
        clear_rate=[math]::Round($clearRate,3)
        average_score=[math]::Round($avgScore,3)
        escalation_rate=[math]::Round($escalationRate,3)
        affinity_index=(ToIndex100 $score)
    }
}

$integratorCompatibility = @()
foreach ($key in $integratorStats.Keys) {
    $x = $integratorStats[$key]
    $samples = [double]$x.samples
    $integrationRate = if ($samples -gt 0) { $x.integration_green / $samples } else { 0.0 }
    $clearRate = if ($samples -gt 0) { $x.mission_clears / $samples } else { 0.0 }
    $escalationRate = if ($samples -gt 0) { $x.escalation_count / $samples } else { 0.0 }
    $avgScore = if ($samples -gt 0) { $x.total_score / $samples } else { 0.0 }

    $score = (
        $integrationRate * 0.40 +
        $clearRate * 0.30 +
        (Clamp01 $avgScore) * 0.20 +
        (1.0 - (Clamp01 $escalationRate)) * 0.10
    )

    $integratorCompatibility += [ordered]@{
        party_model=$x.party_model
        integrator_model=$x.integrator_model
        samples=$x.samples
        integration_green_rate=[math]::Round($integrationRate,3)
        mission_clear_rate=[math]::Round($clearRate,3)
        escalation_rate=[math]::Round($escalationRate,3)
        average_score=[math]::Round($avgScore,3)
        compatibility_index=(ToIndex100 $score)
    }
}

$index = [ordered]@{
    schema='vertex.world.rpg.synergy-affinity-index.v1.1'
    updated_at=(Get-Date).ToString('o')
    battle_logs_processed=$battleFiles.Count

    role_affinity=@($roleAffinity | Sort-Object affinity_index -Descending)
    model_role_affinity=@($modelRoleAffinity | Sort-Object affinity_index -Descending)
    pair_synergy=@($pairSynergy | Sort-Object synergy_index -Descending)
    equipment_affinity=@($equipmentAffinity | Sort-Object affinity_index -Descending)
    formation_affinity=@($formationAffinity | Sort-Object affinity_index -Descending)
    integrator_compatibility=@($integratorCompatibility | Sort-Object compatibility_index -Descending)

    interpretation=[ordered]@{
        note='Indices are normalized presentation values derived from real execution evidence.'
        parameter_count_is_not_strength=$true
        low_sample_warning='Treat low-sample affinities as provisional.'
    }
}

$indexPath = Join-Path $synergyRoot 'VERTEX_WORLD_SYNERGY_AFFINITY.json'
Write-Json $indexPath $index

$bestRole = $roleAffinity | Sort-Object affinity_index -Descending | Select-Object -First 1
$bestPair = $pairSynergy | Sort-Object synergy_index -Descending | Select-Object -First 1
$bestFormation = $formationAffinity | Sort-Object affinity_index -Descending | Select-Object -First 1
$bestIntegrator = $integratorCompatibility | Sort-Object compatibility_index -Descending | Select-Object -First 1

$summary = [ordered]@{
    schema='vertex.world.rpg.synergy-summary.v1.1'
    updated_at=(Get-Date).ToString('o')
    best_role=$bestRole
    best_pair=$bestPair
    best_formation=$bestFormation
    best_integrator=$bestIntegrator
}

$summaryPath = Join-Path $affinityRoot 'CURRENT_AFFINITY_SUMMARY.json'
Write-Json $summaryPath $summary

$receiptPath = Join-Path $receiptRoot "RPG_SYNERGY_AFFINITY.$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"
Write-Json $receiptPath ([ordered]@{
    schema='vertex.world.rpg.synergy-affinity-engine-receipt.v1.1'
    completed_at=(Get-Date).ToString('o')
    battle_logs_processed=$battleFiles.Count
    output=$indexPath
    summary=$summaryPath
    canonical_mutation='NONE'
    vtc_execution='NONE'
})

Write-Host ''
Write-Host '[ROLE AFFINITY]' -ForegroundColor Cyan
$roleAffinity |
    Sort-Object affinity_index -Descending |
    ForEach-Object {
        Write-Host ("  {0,-16} Affinity {1,3}  samples={2}" -f $_.role,$_.affinity_index,$_.samples)
    }

Write-Host ''
Write-Host '[PAIR SYNERGY]' -ForegroundColor Cyan
$pairSynergy |
    Sort-Object synergy_index -Descending |
    Select-Object -First 5 |
    ForEach-Object {
        Write-Host ("  {0} + {1}  Synergy {2,3}  samples={3}" -f $_.role_a,$_.role_b,$_.synergy_index,$_.samples)
    }

Write-Host ''
Write-Host '[FORMATION]' -ForegroundColor Cyan
$formationAffinity |
    Sort-Object affinity_index -Descending |
    ForEach-Object {
        Write-Host ("  model={0} party={1} width={2} affinity={3}" -f `
            $_.model,$_.logical_party_size,$_.stable_width,$_.affinity_index)
    }

Write-Host ''
Write-Host '[INTEGRATOR COMPATIBILITY]' -ForegroundColor Cyan
$integratorCompatibility |
    Sort-Object compatibility_index -Descending |
    ForEach-Object {
        Write-Host ("  {0} -> {1}  compatibility={2}" -f `
            $_.party_model,$_.integrator_model,$_.compatibility_index)
    }

Write-Host ''
Write-Host "Synergy Index : $indexPath"
Write-Host "Summary       : $summaryPath"
Write-Host "Receipt       : $receiptPath"
Write-Host ''
Write-Host 'ALL AFFINITIES ARE EVIDENCE-DERIVED.'
Write-Host 'CANONICAL MUTATION : NONE'
Write-Host 'VTC EXECUTION      : NONE'
Write-Host ''
Write-Host 'VERTEX WORLD — SYNERGY ONLINE.'
Write-Host '轟。' -ForegroundColor Green
