#requires -Version 7.0
<#
VERTEX WORLD — AFFINITY CONFIDENCE LAYER V0.1.0

PURPOSE
  Add evidence confidence to existing RPG affinity/synergy metrics.

KEY IDEA
  Affinity score != confidence.
  A perfect score with one sample remains provisional.

CONFIDENCE TIERS
  1-4     : PROVISIONAL
  5-19    : EMERGING
  20-49   : TRUSTED
  50+     : ESTABLISHED

SAFETY
  - Reads existing RPG synergy index.
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
$synergyPath = Join-Path $rpgRoot 'synergy\VERTEX_WORLD_SYNERGY_AFFINITY.json'
$outputRoot = Join-Path $rpgRoot 'confidence'
$receiptRoot = Join-Path $rpgRoot 'receipts'

$null = New-Item -ItemType Directory -Force -Path $outputRoot
$null = New-Item -ItemType Directory -Force -Path $receiptRoot

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

function Get-ConfidenceTier([int]$Samples) {
    if ($Samples -ge 50) { return 'ESTABLISHED' }
    if ($Samples -ge 20) { return 'TRUSTED' }
    if ($Samples -ge 5)  { return 'EMERGING' }
    return 'PROVISIONAL'
}

function Get-ConfidenceIndex([int]$Samples) {
    if ($Samples -le 0) { return 0 }

    # Saturating evidence confidence curve.
    $index = 100.0 * (1.0 - [math]::Exp(-1.0 * $Samples / 12.0))
    return [int][math]::Round([math]::Min(100.0,$index))
}

function Get-ShrinkageScore {
    param(
        [double]$RawScore,
        [int]$Samples,
        [double]$Prior=50.0,
        [double]$PriorWeight=4.0
    )

    $weighted = (
        ($RawScore * $Samples) +
        ($Prior * $PriorWeight)
    ) / ($Samples + $PriorWeight)

    return [math]::Round($weighted,1)
}

function Add-Confidence {
    param(
        $Entry,
        [string]$ScoreField
    )

    $samples = [int](Get-Prop $Entry 'samples' 0)
    $raw = [double](Get-Prop $Entry $ScoreField 0)

    return [ordered]@{
        raw_score=$raw
        samples=$samples
        confidence_tier=(Get-ConfidenceTier $samples)
        confidence_index=(Get-ConfidenceIndex $samples)
        conservative_score=(Get-ShrinkageScore -RawScore $raw -Samples $samples)
        evidence_note=if ($samples -lt 5) {
            'Low-sample result. Treat as provisional.'
        }
        elseif ($samples -lt 20) {
            'Pattern emerging; more evidence required.'
        }
        elseif ($samples -lt 50) {
            'Trusted pattern with meaningful evidence.'
        }
        else {
            'Established pattern with deep evidence.'
        }
    }
}

Banner 'VERTEX WORLD — AFFINITY CONFIDENCE LAYER V0.1.0'

$index = Read-JsonSafe $synergyPath
if ($null -eq $index) {
    throw "Synergy/Affinity index not found or unreadable: $synergyPath"
}

Write-Host "Source : $synergyPath"

$roleOut = @()
foreach ($e in @(Get-Prop $index 'role_affinity' @())) {
    $roleOut += [ordered]@{
        role=Get-Prop $e 'role' ''
        class=Get-Prop $e 'class' ''
        affinity_index=Get-Prop $e 'affinity_index' 0
        samples=Get-Prop $e 'samples' 0
        confidence=(Add-Confidence -Entry $e -ScoreField 'affinity_index')
    }
}

$modelRoleOut = @()
foreach ($e in @(Get-Prop $index 'model_role_affinity' @())) {
    $modelRoleOut += [ordered]@{
        model=Get-Prop $e 'model' ''
        role=Get-Prop $e 'role' ''
        affinity_index=Get-Prop $e 'affinity_index' 0
        samples=Get-Prop $e 'samples' 0
        confidence=(Add-Confidence -Entry $e -ScoreField 'affinity_index')
    }
}

$pairOut = @()
foreach ($e in @(Get-Prop $index 'pair_synergy' @())) {
    $pairOut += [ordered]@{
        role_a=Get-Prop $e 'role_a' ''
        role_b=Get-Prop $e 'role_b' ''
        synergy_index=Get-Prop $e 'synergy_index' 0
        samples=Get-Prop $e 'samples' 0
        confidence=(Add-Confidence -Entry $e -ScoreField 'synergy_index')
    }
}

$equipmentOut = @()
foreach ($e in @(Get-Prop $index 'equipment_affinity' @())) {
    $equipmentOut += [ordered]@{
        model=Get-Prop $e 'model' ''
        tool=Get-Prop $e 'tool' ''
        affinity_index=Get-Prop $e 'affinity_index' 0
        samples=Get-Prop $e 'samples' 0
        confidence=(Add-Confidence -Entry $e -ScoreField 'affinity_index')
    }
}

$formationOut = @()
foreach ($e in @(Get-Prop $index 'formation_affinity' @())) {
    $formationOut += [ordered]@{
        model=Get-Prop $e 'model' ''
        logical_party_size=Get-Prop $e 'logical_party_size' 0
        stable_width=Get-Prop $e 'stable_width' 0
        affinity_index=Get-Prop $e 'affinity_index' 0
        samples=Get-Prop $e 'samples' 0
        confidence=(Add-Confidence -Entry $e -ScoreField 'affinity_index')
    }
}

$integratorOut = @()
foreach ($e in @(Get-Prop $index 'integrator_compatibility' @())) {
    $integratorOut += [ordered]@{
        party_model=Get-Prop $e 'party_model' ''
        integrator_model=Get-Prop $e 'integrator_model' ''
        compatibility_index=Get-Prop $e 'compatibility_index' 0
        samples=Get-Prop $e 'samples' 0
        confidence=(Add-Confidence -Entry $e -ScoreField 'compatibility_index')
    }
}

$output = [ordered]@{
    schema='vertex.world.rpg.affinity-confidence.v1'
    updated_at=(Get-Date).ToString('o')
    confidence_rules=[ordered]@{
        PROVISIONAL='1-4 samples'
        EMERGING='5-19 samples'
        TRUSTED='20-49 samples'
        ESTABLISHED='50+ samples'
    }
    shrinkage=[ordered]@{
        prior_score=50
        prior_weight=4
        note='Conservative score pulls low-sample metrics toward neutral 50.'
    }
    role_affinity=$roleOut
    model_role_affinity=$modelRoleOut
    pair_synergy=$pairOut
    equipment_affinity=$equipmentOut
    formation_affinity=$formationOut
    integrator_compatibility=$integratorOut
}

$outputPath = Join-Path $outputRoot 'VERTEX_WORLD_AFFINITY_CONFIDENCE.json'
Write-Json $outputPath $output

$summary = [ordered]@{
    schema='vertex.world.rpg.affinity-confidence-summary.v1'
    updated_at=(Get-Date).ToString('o')
    role_top=($roleOut | Sort-Object { $_.confidence.conservative_score } -Descending | Select-Object -First 1)
    pair_top=($pairOut | Sort-Object { $_.confidence.conservative_score } -Descending | Select-Object -First 1)
    formation_top=($formationOut | Sort-Object { $_.confidence.conservative_score } -Descending | Select-Object -First 1)
    integrator_top=($integratorOut | Sort-Object { $_.confidence.conservative_score } -Descending | Select-Object -First 1)
}

$summaryPath = Join-Path $outputRoot 'CURRENT_CONFIDENCE_SUMMARY.json'
Write-Json $summaryPath $summary

$receiptPath = Join-Path $receiptRoot "AFFINITY_CONFIDENCE.$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"
Write-Json $receiptPath ([ordered]@{
    schema='vertex.world.rpg.affinity-confidence-receipt.v1'
    completed_at=(Get-Date).ToString('o')
    source=$synergyPath
    output=$outputPath
    summary=$summaryPath
    canonical_mutation='NONE'
    vtc_execution='NONE'
})

Write-Host ''
Write-Host '[ROLE AFFINITY CONFIDENCE]' -ForegroundColor Cyan
foreach ($e in $roleOut) {
    Write-Host ("  {0,-16} raw={1,3} conservative={2,5} samples={3,-3} {4}" -f `
        $e.role,
        $e.affinity_index,
        $e.confidence.conservative_score,
        $e.samples,
        $e.confidence.confidence_tier
    )
}

Write-Host ''
Write-Host '[PAIR SYNERGY CONFIDENCE]' -ForegroundColor Cyan
foreach ($e in ($pairOut | Select-Object -First 5)) {
    Write-Host ("  {0} + {1} raw={2,3} conservative={3,5} samples={4,-3} {5}" -f `
        $e.role_a,
        $e.role_b,
        $e.synergy_index,
        $e.confidence.conservative_score,
        $e.samples,
        $e.confidence.confidence_tier
    )
}

Write-Host ''
Write-Host '[FORMATION CONFIDENCE]' -ForegroundColor Cyan
foreach ($e in $formationOut) {
    Write-Host ("  model={0} party={1} width={2} raw={3} conservative={4} {5}" -f `
        $e.model,
        $e.logical_party_size,
        $e.stable_width,
        $e.affinity_index,
        $e.confidence.conservative_score,
        $e.confidence.confidence_tier
    )
}

Write-Host ''
Write-Host '[INTEGRATOR CONFIDENCE]' -ForegroundColor Cyan
foreach ($e in $integratorOut) {
    Write-Host ("  {0} -> {1} raw={2} conservative={3} {4}" -f `
        $e.party_model,
        $e.integrator_model,
        $e.compatibility_index,
        $e.confidence.conservative_score,
        $e.confidence.confidence_tier
    )
}

Write-Host ''
Write-Host "Confidence Index : $outputPath"
Write-Host "Summary          : $summaryPath"
Write-Host "Receipt          : $receiptPath"
Write-Host ''
Write-Host 'AFFINITY SCORE AND EVIDENCE CONFIDENCE ARE NOW SEPARATE.'
Write-Host 'CANONICAL MUTATION : NONE'
Write-Host 'VTC EXECUTION      : NONE'
Write-Host ''
Write-Host 'VERTEX WORLD — CONFIDENCE ONLINE.'
Write-Host '轟。' -ForegroundColor Green
