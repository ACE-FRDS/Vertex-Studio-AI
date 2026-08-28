#requires -Version 7.0
<#
VERTEX ARD — ADAPTIVE PARALLEL WIDTH EXPERIMENT
V0.1.0

PURPOSE
  Demonstrate:
    - Logical Party != Physical Concurrency
    - Adaptive Parallel Width
    - Wave Scheduler
    - HTTP 500 Backoff
    - Same-model local runtime saturation handling
    - Party result aggregation
    - Integrator + escalation

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
    [int]$InitialParallelWidth = 4,
    [int]$MinParallelWidth = 1,
    [int]$MaxTokens = 768,
    [int]$TimeoutSec = 180,
    [int]$MaxWaveRetries = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VxnRoot)) {
    $VxnRoot = Join-Path $ProjectRoot 'VXN'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runId = "VXN-ARD-WAVE-$stamp"
$runRoot = Join-Path $VxnRoot "experiments\ard_parallel_width\$runId"
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

        if ($Map.Contains($f)) {
            $ok = $true
        }
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

    $json = $body | ConvertTo-Json -Depth 30 -Compress
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $raw = Invoke-RestMethod `
            -Method Post `
            -Uri 'http://127.0.0.1:1234/v1/chat/completions' `
            -ContentType 'application/json' `
            -Body $json `
            -TimeoutSec $TimeoutSec

        $sw.Stop()

        $choice = $raw.choices[0]
        $msg = $choice.message

        $content = [string](Get-SafeProp $msg 'content' '')
        $reasoning = [string](Get-SafeProp $msg 'reasoning_content' '')

        if ([string]::IsNullOrWhiteSpace($reasoning)) {
            $reasoning = [string](Get-SafeProp $msg 'reasoning' '')
        }

        return [pscustomobject]@{
            Success=$true
            StatusCode=200
            Content=$content
            Reasoning=$reasoning
            LatencyMs=$sw.ElapsedMilliseconds
            PromptTokens=Get-SafeProp $raw.usage 'prompt_tokens' $null
            CompletionTokens=Get-SafeProp $raw.usage 'completion_tokens' $null
            FinishReason=[string](Get-SafeProp $choice 'finish_reason' '')
            Error=''
            Raw=$raw
        }
    }
    catch {
        $sw.Stop()

        $statusCode = 0
        try {
            $statusCode = [int]$_.Exception.Response.StatusCode
        } catch {}

        return [pscustomobject]@{
            Success=$false
            StatusCode=$statusCode
            Content=''
            Reasoning=''
            LatencyMs=$sw.ElapsedMilliseconds
            PromptTokens=$null
            CompletionTokens=$null
            FinishReason=''
            Error=$_.Exception.Message
            Raw=$null
        }
    }
}

function Invoke-PartyWave {
    param(
        [array]$Roles,
        [string]$Model,
        [string]$Mission,
        [int]$WaveNumber,
        [int]$Width
    )

    $jobs = @()

    foreach ($role in $Roles) {
        $jobs += Start-ThreadJob -Name "$WaveNumber-$($role.name)" -ArgumentList @(
            $Model,
            $role.name,
            $role.instruction,
            $Mission,
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
You are one member of a VXN ARD small-model party.

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
                    StatusCode=200
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

                $statusCode = 0
                try {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                } catch {}

                [pscustomobject]@{
                    Role=$RoleName
                    Success=$false
                    StatusCode=$statusCode
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

    $results = @()

    foreach ($job in $jobs) {
        $r = Receive-Job -Job $job
        $results += $r
        Remove-Job -Job $job -Force
    }

    return @($results)
}

Banner 'VERTEX ARD — ADAPTIVE PARALLEL WIDTH EXPERIMENT V0.1.0'

Write-Host "Run ID        : $runId"
Write-Host "Party Size    : $PartySize"
Write-Host "Initial Width : $InitialParallelWidth"
Write-Host "Min Width     : $MinParallelWidth"
Write-Host "Run Root      : $runRoot"

$models = @(Get-LMStudioModels)
$small = Select-TierModel $models 'SMALL'
$m8 = Select-TierModel $models '8B'
$m12 = Select-TierModel $models '12B'
$m30 = Select-TierModel $models '30B'

Write-Host ''
Write-Host '[1/7] MODEL REGISTRY'
Write-Host "  SMALL : $small"
Write-Host "  8B    : $m8"
Write-Host "  12B   : $m12"
Write-Host "  30B   : $m30"

if ([string]::IsNullOrWhiteSpace($small)) {
    throw 'No 3B/4B model available.'
}

$roles = @(
    @{name='Explorer'; instruction='Extract facts, unknowns, dependencies, and evidence gaps.'},
    @{name='Planner'; instruction='Create a minimal-scope candidate plan preserving unrelated state.'},
    @{name='Critic'; instruction='Find failure modes, contradictions, unsafe assumptions, and rollback gaps.'},
    @{name='ScopeGuard'; instruction='Focus on allowed scope, locked scope, authority, human gate, and mutation boundaries.'},
    @{name='Verifier'; instruction='Check whether claims are supported and identify missing evidence.'},
    @{name='Optimizer'; instruction='Reduce unnecessary work without violating scope or safety.'}
)

if ($PartySize -lt 1) { $PartySize = 1 }
if ($PartySize -gt $roles.Count) { $PartySize = $roles.Count }

$selectedRoles = @($roles | Select-Object -First $PartySize)

$mission = @'
MISSION:
Analyze a legacy-sensitive software change.

Requirements:
- Preserve all unrelated UI and data model state.
- Separate facts from assumptions.
- Identify risks and unknowns.
- Produce candidate-only actions.
- Never claim execution.
- Human approval is required before mutation.
- Do not widen scope.
'@

Write-Host ''
Write-Host '[2/7] LOGICAL PARTY'
Write-Host "  Logical Agents : $PartySize"
Write-Host "  Physical Width : $InitialParallelWidth"
Write-Host "  Small Model    : $small"

$pending = New-Object System.Collections.Generic.List[object]
foreach ($r in $selectedRoles) { $pending.Add([pscustomobject]$r) }

$allResults = New-Object System.Collections.Generic.List[object]
$waveReceipts = New-Object System.Collections.Generic.List[object]

$currentWidth = [math]::Max($MinParallelWidth,[math]::Min($InitialParallelWidth,$PartySize))
$wave = 0

Write-Host ''
Write-Host '[3/7] ADAPTIVE WAVE SCHEDULER'

while ($pending.Count -gt 0) {
    $wave++
    $take = [math]::Min($currentWidth,$pending.Count)

    $waveRoles = @()
    for ($i=0; $i -lt $take; $i++) {
        $waveRoles += $pending[0]
        $pending.RemoveAt(0)
    }

    Write-Host ''
    Write-Host "  >>> WAVE $wave" -ForegroundColor Cyan
    Write-Host "      Width : $currentWidth"
    Write-Host "      Roles : $(($waveRoles | ForEach-Object {$_.name}) -join ', ')"

    $attempt = 0
    $waveDone = $false

    while (-not $waveDone -and $attempt -lt $MaxWaveRetries) {
        $attempt++

        $results = @(Invoke-PartyWave `
            -Roles $waveRoles `
            -Model $small `
            -Mission $mission `
            -WaveNumber $wave `
            -Width $currentWidth)

        $successes = @($results | Where-Object {$_.Success})
        $failures = @($results | Where-Object {-not $_.Success})
        $server500 = @($failures | Where-Object {$_.StatusCode -eq 500})

        foreach ($r in $results) {
            if ($r.Success) {
                Write-Host "      RETURN : $($r.Role) latency=$($r.LatencyMs)ms"
            }
            else {
                Write-Host "      ERROR  : $($r.Role) status=$($r.StatusCode) $($r.Error)" -ForegroundColor Red
            }
        }

        $waveReceipts.Add([pscustomobject][ordered]@{
            wave=$wave
            attempt=$attempt
            requested_width=$currentWidth
            roles=@($waveRoles | ForEach-Object {$_.name})
            success_count=$successes.Count
            failure_count=$failures.Count
            http500_count=$server500.Count
        })

        foreach ($s in $successes) {
            $allResults.Add($s)
        }

        if ($failures.Count -eq 0) {
            $waveDone = $true

            # Conservative probe-up: only increase if we previously backed off
            if ($currentWidth -lt $InitialParallelWidth) {
                $currentWidth++
                Write-Host "      WIDTH  : stable -> probe up to $currentWidth" -ForegroundColor Green
            }
        }
        else {
            # Requeue failed roles only.
            $failedNames = @($failures | ForEach-Object {$_.Role})
            $retryRoles = @($waveRoles | Where-Object {$failedNames -contains $_.name})

            if ($server500.Count -gt 0 -and $currentWidth -gt $MinParallelWidth) {
                $old = $currentWidth
                $currentWidth = [math]::Max($MinParallelWidth,$currentWidth - 1)
                Write-Host "      BACKOFF: HTTP 500 detected, width $old -> $currentWidth" -ForegroundColor Yellow
            }
            else {
                Write-Host "      RETRY  : same width $currentWidth" -ForegroundColor Yellow
            }

            # If wave attempt remains, retry failed roles now.
            if ($attempt -lt $MaxWaveRetries) {
                $waveRoles = $retryRoles
            }
            else {
                foreach ($rr in $retryRoles) {
                    $pending.Insert(0,$rr)
                }
                $waveDone = $true
            }
        }
    }
}

Write-Json (Join-Path $runRoot 'PARTY_RESULTS.json') @($allResults.ToArray())
Write-Json (Join-Path $runRoot 'WAVE_RECEIPTS.json') @($waveReceipts.ToArray())

Write-Host ''
Write-Host '[4/7] PARTY SUMMARY'
Write-Host "  Successful Roles : $($allResults.Count)/$PartySize"
Write-Host "  Final Width      : $currentWidth"

$bundle = ""

foreach ($r in $allResults) {
    $bundle += @"

=== ROLE: $($r.Role) ===
$($r.Content)

"@
}

$integratorModel = if (-not [string]::IsNullOrWhiteSpace($m8)) { $m8 } else { $small }

Write-Host ''
Write-Host '[5/7] INTEGRATOR'
Write-Host "  Model : $integratorModel"

$integratorSystem = @'
You are the VXN ARD Integrator.

Synthesize the party outputs.
Resolve contradictions.
Prefer explicit evidence.
Preserve unrelated state.
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
$integrationMap = Find-JsonObject $integrationText
$integrationScore = Score-IntegratedResult $integrationMap

Set-Content -LiteralPath (Join-Path $runRoot 'INTEGRATED_TEXT.txt') -Value $integrationText -Encoding UTF8

if ($null -ne $integrationMap) {
    Write-Json (Join-Path $runRoot 'INTEGRATED_RESULT.json') $integrationMap
}

Write-Host "  Score : $($integrationScore.Score)"
Write-Host "  Green : $($integrationScore.Green)"

$finalScore = $integrationScore
$finalModel = $integratorModel
$finalMap = $integrationMap
$escalationUsed = $false

Write-Host ''
Write-Host '[6/7] ESCALATION'

if (-not $integrationScore.Green) {
    $order = @(
        @{Tier='12B'; Model=$m12},
        @{Tier='30B'; Model=$m30}
    )

    foreach ($candidate in $order) {
        if ([string]::IsNullOrWhiteSpace($candidate.Model)) { continue }

        Write-Host "  ESCALATE -> $($candidate.Tier) : $($candidate.Model)" -ForegroundColor Yellow

        $reviewSystem = @'
You are the senior VXN ARD Reviewer.

Repair the integrated candidate only where necessary.
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

INTEGRATED RESULT:
$integrationText
"@

        $reviewCall = Invoke-Model `
            -Model $candidate.Model `
            -System $reviewSystem `
            -Prompt $reviewPrompt

        $reviewText = Clean-Text $reviewCall.Content $reviewCall.Reasoning
        $reviewMap = Find-JsonObject $reviewText
        $reviewScore = Score-IntegratedResult $reviewMap

        Write-Host "  Score : $($reviewScore.Score)"
        Write-Host "  Green : $($reviewScore.Green)"

        $escalationUsed = $true
        $finalScore = $reviewScore
        $finalModel = $candidate.Model
        $finalMap = $reviewMap

        if ($null -ne $reviewMap) {
            Write-Json (Join-Path $runRoot "REVIEW_$($candidate.Tier).json") $reviewMap
        }

        if ($reviewScore.Green) { break }
    }
}
else {
    Write-Host '  NOT REQUIRED' -ForegroundColor Green
}

Write-Host ''
Write-Host '[7/7] RECEIPT'

$status = if ($finalScore.Green) { 'GREEN' } else { 'NOT_GREEN' }

$receipt = [ordered]@{
    schema='vertex.ard.adaptive-parallel-width-experiment.v1'
    run_id=$runId
    completed_at=(Get-Date).ToString('o')
    status=$status

    logical_party_size=$PartySize
    initial_parallel_width=$InitialParallelWidth
    final_parallel_width=$currentWidth

    wave_scheduler=[ordered]@{
        waves=$wave
        receipts=@($waveReceipts.ToArray())
    }

    party=[ordered]@{
        model=$small
        successful_roles=$allResults.Count
        results=@($allResults.ToArray())
    }

    integrator=[ordered]@{
        model=$integratorModel
        score=$integrationScore.Score
        green=$integrationScore.Green
    }

    escalation=[ordered]@{
        used=$escalationUsed
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

$receiptPath = Join-Path $runRoot 'VERTEX_ARD_ADAPTIVE_PARALLEL_WIDTH_RECEIPT.json'
Write-Json $receiptPath $receipt

Write-Host "  Status  : $status"
Write-Host "  Receipt : $receiptPath"

Banner 'VERTEX ARD ADAPTIVE PARALLEL WIDTH COMPLETE'

Write-Host "Logical Party       : $PartySize"
Write-Host "Initial Width       : $InitialParallelWidth"
Write-Host "Final Width         : $currentWidth"
Write-Host "Successful Roles    : $($allResults.Count)"
Write-Host "Integrator          : $integratorModel"
Write-Host "Escalation Used     : $escalationUsed"
Write-Host "Final Model         : $finalModel"
Write-Host "Final Score         : $($finalScore.Score)"
Write-Host "Final Green         : $($finalScore.Green)"
Write-Host ''
Write-Host 'CANONICAL MUTATION  : NONE'
Write-Host 'VTC EXECUTION       : NONE'

if ($finalScore.Green) {
    Write-Host ''
    Write-Host 'ARD PARTY PATH REACHED GREEN.' -ForegroundColor Green
}

Write-Host '轟。' -ForegroundColor Green
