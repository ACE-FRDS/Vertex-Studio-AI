#requires -Version 7.0
<#
VERTEX ARD — PARALLEL PARTY BOOSTER EXPERIMENT
V0.1.0

PURPOSE
  Demonstrate:
    - Parallelism Throttle
    - Small-model party spawning
    - Parallel subtask execution
    - Result synthesis
    - Reliability scoring
    - Escalation only when party synthesis remains insufficient

ARCHITECTURE
  Mission
    -> Parallelism decision
    -> Spawn 3B/4B party
    -> Parallel roles
         Explorer
         Planner
         Critic
         ScopeGuard
    -> Integrator
    -> Reliability evaluation
    -> GREEN or escalate

SAFETY
  - No OS mutation.
  - No canonical mutation.
  - No VTC execution.
  - Candidate-only reasoning.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'G:\Vertex_Project\Vertex_Studio_AI',
    [string]$VxnRoot = '',
    [int]$PartySize = 4,
    [int]$MaxTokens = 768,
    [int]$TimeoutSec = 180,
    [switch]$ForceEscalation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VxnRoot)) {
    $VxnRoot = Join-Path $ProjectRoot 'VXN'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runId = "VXN-ARD-PARALLEL-$stamp"
$runRoot = Join-Path $VxnRoot "experiments\ard_parallel\$runId"
$null = New-Item -ItemType Directory -Path $runRoot -Force

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

function Invoke-JsonPost([string]$Uri, $Body) {
    $json = $Body | ConvertTo-Json -Depth 40 -Compress
    Invoke-RestMethod -Method Post -Uri $Uri -ContentType 'application/json' -Body $json -TimeoutSec $TimeoutSec
}

function Get-SafeProp {
    param($Object,[string]$Name,$Default=$null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Get-LMStudioModels {
    $r = Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:1234/v1/models' -TimeoutSec 5
    return @($r.data | ForEach-Object { [string]$_.id } | Where-Object { $_ })
}

function Get-ModelSizeInfo {
    param([string]$ModelId)

    $id = $ModelId.ToLowerInvariant()
    $clean = $id -replace '(?i)a\d+(?:\.\d+)?b', ''
    $matches = [regex]::Matches($clean, '(?<![a-z0-9])(\d+(?:\.\d+)?)b(?![a-z0-9])')

    $sizes = @()
    foreach ($m in $matches) {
        $v = 0.0
        if ([double]::TryParse($m.Groups[1].Value,[ref]$v)) {
            $sizes += $v
        }
    }

    if ($sizes.Count -eq 0) {
        return [pscustomobject]@{Model=$ModelId; PrimarySize=$null}
    }

    [pscustomobject]@{
        Model=$ModelId
        PrimarySize=[double](($sizes | Measure-Object -Maximum).Maximum)
    }
}

function Select-TierModel {
    param([string[]]$Models,[string]$Tier)

    $wanted = switch ($Tier) {
        'SMALL' { @{Min=2.5; Max=4.5; Target=4.0} }
        '8B'    { @{Min=7.0; Max=9.0; Target=8.0} }
        '12B'   { @{Min=11.0; Max=15.0; Target=12.0} }
        '30B'   { @{Min=26.0; Max=35.0; Target=30.0} }
    }

    $candidates = @()

    foreach ($m in $Models) {
        $info = Get-ModelSizeInfo $m
        if ($null -eq $info.PrimarySize) { continue }

        $s = [double]$info.PrimarySize
        if ($s -ge $wanted.Min -and $s -le $wanted.Max) {
            $candidates += [pscustomobject]@{
                Model=$m
                Size=$s
                Distance=[math]::Abs($s-$wanted.Target)
            }
        }
    }

    if ($candidates.Count -eq 0) { return '' }

    return [string](($candidates |
        Sort-Object Distance, Size, Model |
        Select-Object -First 1).Model)
}

function Invoke-Model {
    param(
        [string]$Model,
        [string]$System,
        [string]$Prompt
    )

    $body = @{
        model=$Model
        messages=@(
            @{role='system'; content=$System},
            @{role='user'; content=$Prompt}
        )
        temperature=0.1
        max_tokens=$MaxTokens
        stream=$false
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $raw = Invoke-JsonPost 'http://127.0.0.1:1234/v1/chat/completions' $body
    $sw.Stop()

    $choice = $raw.choices[0]
    $msg = $choice.message
    $usage = Get-SafeProp $raw 'usage' $null

    $content = [string](Get-SafeProp $msg 'content' '')
    $reasoning = [string](Get-SafeProp $msg 'reasoning_content' '')
    if ([string]::IsNullOrWhiteSpace($reasoning)) {
        $reasoning = [string](Get-SafeProp $msg 'reasoning' '')
    }

    $completion = Get-SafeProp $usage 'completion_tokens' $null
    $tps = $null
    if ($null -ne $completion -and $sw.Elapsed.TotalSeconds -gt 0) {
        $tps = [math]::Round(([double]$completion / $sw.Elapsed.TotalSeconds),3)
    }

    [pscustomobject]@{
        Content=$content
        Reasoning=$reasoning
        LatencyMs=$sw.ElapsedMilliseconds
        PromptTokens=Get-SafeProp $usage 'prompt_tokens' $null
        CompletionTokens=$completion
        TokensPerSec=$tps
        FinishReason=[string](Get-SafeProp $choice 'finish_reason' '')
        Raw=$raw
    }
}

function Clean-Text([string]$Content,[string]$Reasoning) {
    $t = $Content
    if ([string]::IsNullOrWhiteSpace($t)) { $t = $Reasoning }
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }

    $t = [regex]::Replace($t,'(?is)<think>.*?</think>','').Trim()
    $t = $t -replace '^```(?:json|text)?\s*',''
    $t = $t -replace '\s*```$',''
    return $t.Trim()
}

function Find-JsonObject([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    try {
        $o = $Text | ConvertFrom-Json -AsHashtable
        if ($o -is [System.Collections.IDictionary]) { return $o }
    } catch {}

    $start = $Text.IndexOf('{')
    if ($start -lt 0) { return $null }

    $depth = 0
    $inString = $false
    $escape = $false

    for ($i=$start; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]

        if ($inString) {
            if ($escape) { $escape=$false; continue }
            if ($c -eq '\') { $escape=$true; continue }
            if ($c -eq '"') { $inString=$false }
            continue
        }

        if ($c -eq '"') { $inString=$true; continue }
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) {
                $candidate = $Text.Substring($start,$i-$start+1)
                try {
                    return $candidate | ConvertFrom-Json -AsHashtable
                } catch {
                    return $null
                }
            }
        }
    }

    return $null
}

function Score-IntegratedResult {
    param($Map)

    if ($null -eq $Map) {
        return [pscustomobject]@{
            Score=0.0
            Green=$false
            Missing=@('ALL')
        }
    }

    $required = @(
        'status',
        'intent',
        'facts',
        'assumptions',
        'allowed_scope',
        'locked_scope',
        'candidate_actions',
        'risks',
        'unknowns',
        'requires_human_gate'
    )

    $missing = @()
    $present = 0

    foreach ($f in $required) {
        $ok = $false
        if ($Map.Contains($f)) { $ok = $true }
        else {
            try {
                if ($Map.ContainsKey($f)) { $ok = $true }
            } catch {}
        }

        if ($ok) { $present++ } else { $missing += $f }
    }

    $schema = $present / [double]$required.Count

    $scopeScore = 0.0
    $lockScore = 0.0
    $riskScore = 0.0
    $unknownScore = 0.0
    $humanScore = 0.0

    if (@($Map['allowed_scope']).Count -gt 0) { $scopeScore=1.0 }
    if (@($Map['locked_scope']).Count -gt 0) { $lockScore=1.0 }
    if (@($Map['risks']).Count -gt 0) { $riskScore=1.0 }
    if (@($Map['unknowns']).Count -gt 0) { $unknownScore=1.0 }
    if ($Map['requires_human_gate'] -eq $true) { $humanScore=1.0 }

    $score = (
        $schema * 0.35 +
        $scopeScore * 0.15 +
        $lockScore * 0.15 +
        $riskScore * 0.10 +
        $unknownScore * 0.10 +
        $humanScore * 0.15
    )

    [pscustomobject]@{
        Score=[math]::Round($score,3)
        Green=($score -ge 0.90 -and $missing.Count -eq 0)
        Missing=$missing
    }
}

Banner 'VERTEX ARD — PARALLEL PARTY BOOSTER EXPERIMENT V0.1.0'

Write-Host "Run ID     : $runId"
Write-Host "Party Size : $PartySize"
Write-Host "MaxTokens  : $MaxTokens"
Write-Host "Run Root   : $runRoot"

$models = @(Get-LMStudioModels)

$small = Select-TierModel $models 'SMALL'
$m8 = Select-TierModel $models '8B'
$m12 = Select-TierModel $models '12B'
$m30 = Select-TierModel $models '30B'

Write-Host ''
Write-Host '[1/6] MODEL REGISTRY'
Write-Host "  SMALL : $small"
Write-Host "  8B    : $m8"
Write-Host "  12B   : $m12"
Write-Host "  30B   : $m30"

if ([string]::IsNullOrWhiteSpace($small)) {
    throw 'No 3B/4B model available for parallel party.'
}

$mission = @'
MISSION:
Analyze a legacy-sensitive software change.

Requirements:
- Preserve all unrelated UI and data model state.
- Separate facts from assumptions.
- Identify risks and unknowns.
- Produce candidate-only actions.
- Never claim execution.
- Human approval is required before any mutation.
- Do not widen scope.
- Return concise, structured reasoning for your assigned role only.
'@

$roles = @(
    @{
        name='Explorer'
        instruction='Extract facts, unknowns, dependencies, and evidence gaps.'
    },
    @{
        name='Planner'
        instruction='Create a minimal-scope candidate plan while preserving unrelated state.'
    },
    @{
        name='Critic'
        instruction='Attack the plan: find failure modes, contradictions, unsafe assumptions, and missing rollback concerns.'
    },
    @{
        name='ScopeGuard'
        instruction='Focus only on allowed scope, locked scope, authority, human gate, and mutation boundaries.'
    }
)

if ($PartySize -lt 1) { $PartySize = 1 }
if ($PartySize -gt $roles.Count) { $PartySize = $roles.Count }

$selectedRoles = @($roles | Select-Object -First $PartySize)

Write-Host ''
Write-Host '[2/6] PARALLELISM THROTTLE'
Write-Host "  Mode      : PARTY"
Write-Host "  Throttle  : $([math]::Min(100,25 + ($PartySize * 15)))%"
Write-Host "  Agents    : $PartySize"
Write-Host "  Model     : $small"

$jobs = @()

Write-Host ''
Write-Host '[3/6] SPAWN SMALL-MODEL PARTY'

foreach ($role in $selectedRoles) {
    $roleName = $role.name
    $roleInstruction = $role.instruction

    Write-Host "  SPAWN : $roleName"

    $jobs += Start-ThreadJob -Name $roleName -ArgumentList @(
        $small,
        $roleName,
        $roleInstruction,
        $mission,
        $MaxTokens,
        $TimeoutSec
    ) -ScriptBlock {
        param(
            $Model,
            $RoleName,
            $RoleInstruction,
            $Mission,
            $MaxTokensLocal,
            $TimeoutSecLocal
        )

        $system = @"
You are one member of a VXN ARD small-model parallel party.

ROLE: $RoleName
ROLE INSTRUCTION:
$RoleInstruction

RULES:
- Candidate reasoning only.
- Never claim execution.
- Preserve unrelated state.
- Distinguish fact from assumption.
- Be concise.
"@

        $body = @{
            model=$Model
            messages=@(
                @{role='system'; content=$system},
                @{role='user'; content=$Mission}
            )
            temperature=0.1
            max_tokens=$MaxTokensLocal
            stream=$false
        }

        $json = $body | ConvertTo-Json -Depth 30 -Compress
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $raw = Invoke-RestMethod `
                -Method Post `
                -Uri 'http://127.0.0.1:1234/v1/chat/completions' `
                -ContentType 'application/json' `
                -Body $json `
                -TimeoutSec $TimeoutSecLocal

            $sw.Stop()

            $choice = $raw.choices[0]
            $content = [string]$choice.message.content

            if ([string]::IsNullOrWhiteSpace($content)) {
                $rp = $choice.message.PSObject.Properties['reasoning_content']
                if ($null -ne $rp) { $content = [string]$rp.Value }
            }

            [pscustomobject]@{
                Role=$RoleName
                Success=$true
                Content=$content
                LatencyMs=$sw.ElapsedMilliseconds
                PromptTokens=$raw.usage.prompt_tokens
                CompletionTokens=$raw.usage.completion_tokens
                FinishReason=$choice.finish_reason
                Error=''
            }
        }
        catch {
            $sw.Stop()

            [pscustomobject]@{
                Role=$RoleName
                Success=$false
                Content=''
                LatencyMs=$sw.ElapsedMilliseconds
                PromptTokens=$null
                CompletionTokens=$null
                FinishReason=''
                Error=$_.Exception.Message
            }
        }
    }
}

$null = Wait-Job -Job $jobs

$partyResults = @()

foreach ($job in $jobs) {
    $r = Receive-Job -Job $job
    $partyResults += $r
    Remove-Job -Job $job -Force

    if ($r.Success) {
        Write-Host "  RETURN: $($r.Role) latency=$($r.LatencyMs)ms"
    }
    else {
        Write-Host "  ERROR : $($r.Role) $($r.Error)" -ForegroundColor Red
    }
}

Write-Json (Join-Path $runRoot 'PARTY_RESULTS.json') $partyResults

Write-Host ''
Write-Host '[4/6] INTEGRATE PARTY'

$bundle = ""

foreach ($r in $partyResults) {
    if (-not $r.Success) { continue }

    $bundle += @"

=== ROLE: $($r.Role) ===
$($r.Content)

"@
}

$integratorModel = if (-not [string]::IsNullOrWhiteSpace($m8)) { $m8 } else { $small }

$integratorSystem = @'
You are the VXN ARD Integrator.

You receive outputs from multiple small-model party members.

Synthesize them.
Do not blindly vote.
Resolve contradictions.
Prefer explicit evidence and conservative scope.
Do not invent missing history.
Do not claim execution.

RETURN JSON ONLY:
{
  "status":"READY|HOLD|REJECT",
  "intent":"...",
  "facts":["..."],
  "assumptions":["..."],
  "allowed_scope":["..."],
  "locked_scope":["..."],
  "candidate_actions":["..."],
  "risks":["..."],
  "unknowns":["..."],
  "requires_human_gate":true
}
'@

$integrationPrompt = @"
MISSION:
$mission

PARTY OUTPUTS:
$bundle
"@

$integrationCall = Invoke-Model `
    -Model $integratorModel `
    -System $integratorSystem `
    -Prompt $integrationPrompt

$integrationText = Clean-Text $integrationCall.Content $integrationCall.Reasoning
Set-Content -LiteralPath (Join-Path $runRoot 'INTEGRATED_TEXT.txt') -Value $integrationText -Encoding UTF8
Write-Json (Join-Path $runRoot 'INTEGRATION_RAW.json') $integrationCall.Raw

$integrationMap = Find-JsonObject $integrationText

if ($null -ne $integrationMap) {
    Write-Json (Join-Path $runRoot 'INTEGRATED_RESULT.json') $integrationMap
}

$score = Score-IntegratedResult $integrationMap

Write-Host "  Integrator : $integratorModel"
Write-Host "  Score      : $($score.Score)"
Write-Host "  Green      : $($score.Green)"
Write-Host "  Missing    : $($score.Missing -join ', ')"

$escalated = $false
$finalModel = $integratorModel
$finalScore = $score
$finalMap = $integrationMap

if (-not $score.Green -or $ForceEscalation) {
    Write-Host ''
    Write-Host '[5/6] ESCALATION'

    $escalationOrder = @(
        @{Tier='12B'; Model=$m12},
        @{Tier='30B'; Model=$m30}
    )

    foreach ($candidate in $escalationOrder) {
        if ([string]::IsNullOrWhiteSpace($candidate.Model)) { continue }

        Write-Host "  ESCALATE -> $($candidate.Tier) : $($candidate.Model)" -ForegroundColor Yellow

        $reviewSystem = @'
You are the senior VXN ARD Reviewer.

A small-model party and integrator produced a candidate result.
Review and repair only what is necessary.
Preserve valid work.
Do not widen scope.
Do not claim execution.

RETURN JSON ONLY:
{
  "status":"READY|HOLD|REJECT",
  "intent":"...",
  "facts":["..."],
  "assumptions":["..."],
  "allowed_scope":["..."],
  "locked_scope":["..."],
  "candidate_actions":["..."],
  "risks":["..."],
  "unknowns":["..."],
  "requires_human_gate":true
}
'@

        $reviewPrompt = @"
MISSION:
$mission

PARTY + INTEGRATOR RESULT:
$integrationText
"@

        $reviewCall = Invoke-Model `
            -Model $candidate.Model `
            -System $reviewSystem `
            -Prompt $reviewPrompt

        $reviewText = Clean-Text $reviewCall.Content $reviewCall.Reasoning
        $reviewMap = Find-JsonObject $reviewText
        $reviewScore = Score-IntegratedResult $reviewMap

        Write-Host "  Score      : $($reviewScore.Score)"
        Write-Host "  Green      : $($reviewScore.Green)"

        $escalated = $true
        $finalModel = $candidate.Model
        $finalScore = $reviewScore
        $finalMap = $reviewMap

        if ($null -ne $reviewMap) {
            Write-Json (Join-Path $runRoot "REVIEW_$($candidate.Tier).json") $reviewMap
        }

        if ($reviewScore.Green) { break }
    }
}
else {
    Write-Host ''
    Write-Host '[5/6] ESCALATION'
    Write-Host '  NOT REQUIRED' -ForegroundColor Green
}

Write-Host ''
Write-Host '[6/6] RECEIPT'

$status = if ($finalScore.Green) { 'GREEN' } else { 'NOT_GREEN' }

$receipt = [ordered]@{
    schema='vertex.ard.parallel-party-experiment.v1'
    run_id=$runId
    completed_at=(Get-Date).ToString('o')
    status=$status
    party=[ordered]@{
        model=$small
        size=$PartySize
        roles=@($selectedRoles | ForEach-Object { $_.name })
        results=$partyResults
    }
    integrator=[ordered]@{
        model=$integratorModel
        score=$score.Score
        green=$score.Green
    }
    escalation=[ordered]@{
        used=$escalated
        final_model=$finalModel
    }
    final=[ordered]@{
        score=$finalScore.Score
        green=$finalScore.Green
        result=$finalMap
    }
    safety=[ordered]@{
        canonical_mutation='NONE'
        vtc_execution='NONE'
    }
}

$receiptPath = Join-Path $runRoot 'VERTEX_ARD_PARALLEL_PARTY_RECEIPT.json'
Write-Json $receiptPath $receipt

Write-Host "  Status  : $status"
Write-Host "  Receipt : $receiptPath"

Banner 'VERTEX ARD PARALLEL PARTY COMPLETE'

Write-Host "Party Model        : $small"
Write-Host "Party Size         : $PartySize"
Write-Host "Integrator         : $integratorModel"
Write-Host "Escalation Used    : $escalated"
Write-Host "Final Model        : $finalModel"
Write-Host "Final Score        : $($finalScore.Score)"
Write-Host "Final Green        : $($finalScore.Green)"
Write-Host ''
Write-Host 'CANONICAL MUTATION : NONE'
Write-Host 'VTC EXECUTION      : NONE'

if ($finalScore.Green) {
    Write-Host ''
    Write-Host 'ARD SMALL-MODEL PARTY REACHED GREEN.' -ForegroundColor Green
}

Write-Host '轟。' -ForegroundColor Green
