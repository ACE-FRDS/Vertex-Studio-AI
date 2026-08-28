#requires -Version 7.0
<#
VERTEX WORLD — ARD FORMATION EXECUTOR V0.1.0

PURPOSE
  Execute CURRENT_FORMATION_PLAN.json only after explicit GO.
  Uses:
    - Planned roles/models
    - Planned physical parallel width
    - Adaptive width backoff on HTTP 500
    - Integrator from plan
    - Escalation when integration is not green
    - Execution receipt for RPG telemetry/progression

SAFETY
  - Candidate reasoning only.
  - No canonical mutation.
  - No VTC execution.
  - No filesystem mutation outside experiment/runtime receipt outputs.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'G:\Vertex_Project\Vertex_Studio_AI',
    [string]$VxnRoot = '',
    [switch]$Go,
    [int]$MaxTokens = 768,
    [int]$TimeoutSec = 180,
    [int]$MaxWaveRetries = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VxnRoot)) {
    $VxnRoot = Join-Path $ProjectRoot 'VXN'
}

$rpgRoot = Join-Path $VxnRoot 'runtime\rpg'
$formationPath = Join-Path $rpgRoot 'formations\CURRENT_FORMATION_PLAN.json'

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runId = "VXN-FORMATION-EXEC-$stamp"
$runRoot = Join-Path $VxnRoot "experiments\formation_executor\$runId"
$null = New-Item -ItemType Directory -Force -Path $runRoot

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

function Score-Result {
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

    $scopeScore = if (@($Map['allowed_scope']).Count -gt 0) { 1.0 } else { 0.0 }
    $lockScore = if (@($Map['locked_scope']).Count -gt 0) { 1.0 } else { 0.0 }
    $riskScore = if (@($Map['risks']).Count -gt 0) { 1.0 } else { 0.0 }
    $unknownScore = if (@($Map['unknowns']).Count -gt 0) { 1.0 } else { 0.0 }
    $humanScore = if ($Map['requires_human_gate'] -eq $true) { 1.0 } else { 0.0 }

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
        $content = [string](Get-Prop $msg 'content' '')
        $reasoning = [string](Get-Prop $msg 'reasoning_content' '')

        if ([string]::IsNullOrWhiteSpace($reasoning)) {
            $reasoning = [string](Get-Prop $msg 'reasoning' '')
        }

        return [pscustomobject]@{
            Success=$true
            StatusCode=200
            Content=$content
            Reasoning=$reasoning
            LatencyMs=$sw.ElapsedMilliseconds
            PromptTokens=Get-Prop $raw.usage 'prompt_tokens' $null
            CompletionTokens=Get-Prop $raw.usage 'completion_tokens' $null
            FinishReason=[string](Get-Prop $choice 'finish_reason' '')
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

function Invoke-RoleWave {
    param(
        [array]$Members,
        [string]$MissionText
    )

    $jobs = @()

    foreach ($member in $Members) {
        $role = [string](Get-Prop $member 'role' 'Agent')
        $model = [string](Get-Prop $member 'model' '')
        $assignmentStatus = [string](Get-Prop $member 'assignment_status' 'EXPERIENCED')

        $jobs += Start-ThreadJob `
            -Name $role `
            -ArgumentList @(
                $role,
                $model,
                $assignmentStatus,
                $MissionText,
                $MaxTokens,
                $TimeoutSec
            ) `
            -ScriptBlock {
                param(
                    $Role,
                    $Model,
                    $AssignmentStatus,
                    $MissionText,
                    $MaxTokensLocal,
                    $TimeoutSecLocal
                )

                $system = @"
You are a member of a VXN ARD formation.

ROLE: $Role
ASSIGNMENT STATUS: $AssignmentStatus

RULES:
- Candidate reasoning only.
- Never claim execution.
- Preserve unrelated state.
- Separate facts from assumptions.
- Identify risks and unknowns.
- Human approval is required before mutation.
- Return concise role-specific analysis.
"@

                $body = @{
                    model=$Model
                    messages=@(
                        @{role='system'; content=$system},
                        @{role='user'; content=$MissionText}
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
                        if ($null -ne $rp) {
                            $content = [string]$rp.Value
                        }
                    }

                    [pscustomobject]@{
                        Role=$Role
                        Model=$Model
                        AssignmentStatus=$AssignmentStatus
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
                        Role=$Role
                        Model=$Model
                        AssignmentStatus=$AssignmentStatus
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
        $results += Receive-Job -Job $job
        Remove-Job -Job $job -Force
    }

    return @($results)
}

Banner 'VERTEX WORLD — ARD FORMATION EXECUTOR V0.1.0'

$plan = Read-JsonSafe $formationPath

if ($null -eq $plan) {
    throw "Formation plan not found: $formationPath"
}

$formationId = [string](Get-Prop $plan 'formation_id' 'UNKNOWN')
$mission = Get-Prop $plan 'mission' $null
$missionClass = [string](Get-Prop $mission 'class' 'GENERAL')

$party = Get-Prop $plan 'party' $null
$members = @(Get-Prop $party 'roles' @())
$plannedWidth = [int](Get-Prop $party 'physical_parallel_width' 1)

$command = Get-Prop $plan 'command' $null
$integratorModel = [string](Get-Prop $command 'integrator_model' '')

Write-Host "Formation ID : $formationId"
Write-Host "Mission      : $missionClass"
Write-Host "Party Size   : $($members.Count)"
Write-Host "Width        : $plannedWidth"
Write-Host "Integrator   : $integratorModel"

if (-not $Go) {
    Write-Host ''
    Write-Host 'GO SIGNAL : NOT PROVIDED' -ForegroundColor Yellow
    Write-Host 'NO AGENTS EXECUTED.'
    Write-Host ''
    Write-Host 'Run again with -Go to execute this formation.'
    exit 0
}

Write-Host ''
Write-Host 'GO SIGNAL : RECEIVED' -ForegroundColor Green

$missionText = @"
MISSION CLASS: $missionClass

Analyze the mission conservatively.

Requirements:
- Preserve unrelated state.
- Separate facts from assumptions.
- Identify risks and unknowns.
- Produce candidate-only actions.
- Never claim execution.
- Human approval is required before mutation.
- Do not widen scope.
"@

$pending = New-Object System.Collections.Generic.List[object]
foreach ($m in $members) {
    $pending.Add($m)
}

$allResults = New-Object System.Collections.Generic.List[object]
$waveReceipts = New-Object System.Collections.Generic.List[object]

$currentWidth = [math]::Max(1,[math]::Min($plannedWidth,$members.Count))
$stableWidth = $null
$wave = 0

Write-Host ''
Write-Host '[1/5] PARTY EXECUTION'

while ($pending.Count -gt 0) {
    $wave++
    $take = [math]::Min($currentWidth,$pending.Count)

    $waveMembers = @()

    for ($i=0; $i -lt $take; $i++) {
        $waveMembers += $pending[0]
        $pending.RemoveAt(0)
    }

    Write-Host ''
    Write-Host "  >>> WAVE $wave" -ForegroundColor Cyan
    Write-Host "      Width : $currentWidth"
    Write-Host "      Roles : $(($waveMembers | ForEach-Object { $_.role }) -join ', ')"

    $attempt = 0
    $done = $false

    while (-not $done -and $attempt -lt $MaxWaveRetries) {
        $attempt++

        $results = @(Invoke-RoleWave `
            -Members $waveMembers `
            -MissionText $missionText)

        $success = @($results | Where-Object { $_.Success })
        $failed = @($results | Where-Object { -not $_.Success })
        $http500 = @($failed | Where-Object { $_.StatusCode -eq 500 })

        foreach ($r in $results) {
            if ($r.Success) {
                Write-Host "      RETURN : $($r.Role) [$($r.AssignmentStatus)] latency=$($r.LatencyMs)ms"
            }
            else {
                Write-Host "      ERROR  : $($r.Role) status=$($r.StatusCode) $($r.Error)" -ForegroundColor Red
            }
        }

        foreach ($r in $success) {
            $allResults.Add($r)
        }

        $waveReceipts.Add([pscustomobject][ordered]@{
            wave=$wave
            attempt=$attempt
            width=$currentWidth
            success_count=$success.Count
            failure_count=$failed.Count
            http500_count=$http500.Count
        })

        if ($failed.Count -eq 0) {
            $stableWidth = $currentWidth
            $done = $true
        }
        else {
            $failedNames = @($failed | ForEach-Object { $_.Role })
            $retryMembers = @(
                $waveMembers |
                Where-Object { $failedNames -contains $_.role }
            )

            if ($http500.Count -gt 0 -and $currentWidth -gt 1) {
                $oldWidth = $currentWidth
                $currentWidth--
                Write-Host "      BACKOFF: width $oldWidth -> $currentWidth" -ForegroundColor Yellow
            }

            if ($attempt -lt $MaxWaveRetries) {
                $waveMembers = $retryMembers
            }
            else {
                foreach ($rr in $retryMembers) {
                    $pending.Insert(0,$rr)
                }

                $done = $true
            }
        }
    }
}

Write-Json (Join-Path $runRoot 'FORMATION_PARTY_RESULTS.json') @($allResults.ToArray())
Write-Json (Join-Path $runRoot 'FORMATION_WAVES.json') @($waveReceipts.ToArray())

Write-Host ''
Write-Host '[2/5] INTEGRATOR'

$bundle = ""

foreach ($r in $allResults) {
    $bundle += @"

=== ROLE: $($r.Role) ===
ASSIGNMENT: $($r.AssignmentStatus)
MODEL: $($r.Model)

$($r.Content)

"@
}

$integratorSystem = @'
You are the VXN ARD Integrator.

Synthesize the formation outputs.
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
MISSION CLASS:
$missionClass

PARTY OUTPUTS:
$bundle
"@

$integrationCall = Invoke-Model `
    -Model $integratorModel `
    -System $integratorSystem `
    -Prompt $integrationPrompt

$integrationText = Clean-Text `
    $integrationCall.Content `
    $integrationCall.Reasoning

$integrationMap = Find-JsonObject $integrationText
$score = Score-Result $integrationMap

Write-Host "  Score : $($score.Score)"
Write-Host "  Green : $($score.Green)"

Set-Content `
    -LiteralPath (Join-Path $runRoot 'FORMATION_INTEGRATED_TEXT.txt') `
    -Value $integrationText `
    -Encoding UTF8

if ($null -ne $integrationMap) {
    Write-Json `
        (Join-Path $runRoot 'FORMATION_INTEGRATED_RESULT.json') `
        $integrationMap
}

Write-Host ''
Write-Host '[3/5] ESCALATION'

$finalMap = $integrationMap
$finalScore = $score
$finalModel = $integratorModel
$escalationUsed = $false

if (-not $score.Green) {
    $models = @()

    try {
        $modelResponse = Invoke-RestMethod `
            -Method Get `
            -Uri 'http://127.0.0.1:1234/v1/models' `
            -TimeoutSec 5

        $models = @(
            $modelResponse.data |
            ForEach-Object { [string]$_.id }
        )
    }
    catch {}

    $fallbacks = @(
        $models | Where-Object { $_ -match '(?i)(12|13|14)b' } | Select-Object -First 1
        $models | Where-Object { $_ -match '(?i)(30|32|34)b' } | Select-Object -First 1
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($model in $fallbacks) {
        Write-Host "  ESCALATE -> $model" -ForegroundColor Yellow

        $review = Invoke-Model `
            -Model $model `
            -System $integratorSystem `
            -Prompt $integrationPrompt

        $reviewText = Clean-Text $review.Content $review.Reasoning
        $reviewMap = Find-JsonObject $reviewText
        $reviewScore = Score-Result $reviewMap

        $escalationUsed = $true
        $finalMap = $reviewMap
        $finalScore = $reviewScore
        $finalModel = $model

        Write-Host "  Score : $($reviewScore.Score)"
        Write-Host "  Green : $($reviewScore.Green)"

        if ($reviewScore.Green) {
            break
        }
    }
}
else {
    Write-Host '  NOT REQUIRED' -ForegroundColor Green
}

Write-Host ''
Write-Host '[4/5] EXECUTION RECEIPT'

$status = if ($finalScore.Green) { 'GREEN' } else { 'NOT_GREEN' }

$rookieResults = @(
    $allResults |
    Where-Object { $_.AssignmentStatus -eq 'TRIAL_ASSIGNMENT' } |
    ForEach-Object {
        [ordered]@{
            role=$_.Role
            model=$_.Model
            success=$_.Success
            latency_ms=$_.LatencyMs
            status='TRIAL_COMPLETED'
        }
    }
)

$receipt = [ordered]@{
    schema='vertex.world.ard.formation-execution.v1'
    run_id=$runId
    formation_id=$formationId
    mission_class=$missionClass
    completed_at=(Get-Date).ToString('o')
    status=$status

    party=[ordered]@{
        logical_size=$members.Count
        planned_width=$plannedWidth
        stable_width=if ($null -eq $stableWidth) { $currentWidth } else { $stableWidth }
        results=@($allResults.ToArray())
    }

    rookies=$rookieResults

    integrator=[ordered]@{
        model=$integratorModel
        score=$score.Score
        green=$score.Green
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

$receiptPath = Join-Path $runRoot 'VERTEX_ARD_FORMATION_EXECUTION_RECEIPT.json'
Write-Json $receiptPath $receipt

Write-Host "  Status  : $status"
Write-Host "  Receipt : $receiptPath"

Write-Host ''
Write-Host '[5/5] NEXT DATA PATH'

Write-Host '  Formation execution evidence is ready for:'
Write-Host '  1. RPG Telemetry Bridge'
Write-Host '  2. Progression Engine'
Write-Host '  3. Synergy/Affinity Engine'
Write-Host '  4. Confidence Layer'

Banner 'VERTEX WORLD — FORMATION EXECUTION COMPLETE'

Write-Host "Formation        : $formationId"
Write-Host "Mission          : $missionClass"
Write-Host "Party Results    : $($allResults.Count)/$($members.Count)"
Write-Host "Stable Width     : $(if ($null -eq $stableWidth) { $currentWidth } else { $stableWidth })"
Write-Host "Integrator       : $integratorModel"
Write-Host "Escalation Used  : $escalationUsed"
Write-Host "Final Model      : $finalModel"
Write-Host "Final Score      : $($finalScore.Score)"
Write-Host "Final Green      : $($finalScore.Green)"
Write-Host "Rookies Tested   : $($rookieResults.Count)"
Write-Host ''
Write-Host 'CANONICAL MUTATION : NONE'
Write-Host 'VTC EXECUTION      : NONE'

if ($finalScore.Green) {
    Write-Host ''
    Write-Host 'FORMATION MISSION CLEAR.' -ForegroundColor Green
}

Write-Host '轟。' -ForegroundColor Green
