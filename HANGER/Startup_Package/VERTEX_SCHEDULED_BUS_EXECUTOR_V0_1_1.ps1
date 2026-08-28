#requires -Version 7.0
<#
VERTEX — SCHEDULED BUS EXECUTOR V0.1.1

PURPOSE
  Execute the CURRENT_BUS_ROUTE_PLAN only after explicit -Go.

PIPELINE
  Scheduler Plan
    -> Load Balancing Bus Route Plan
    -> Scheduled Bus Executor
    -> Command Integration
    -> Formation-compatible Execution Receipt
    -> Existing RPG Evidence Ingestion

RUNTIME BEHAVIOR
  - Execute field routes in bus order.
  - Preserve successful lane results.
  - Retry failed lanes only.
  - On HTTP 500, reduce effective width by 1, never below minimum.
  - Execute command route only after all field routes complete.
  - No canonical mutation.
  - No VTC execution.

SAFETY
  - Requires explicit -Go.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'G:\Vertex_Project\Vertex_Studio_AI',
    [string]$VxnRoot = '',
    [switch]$Go,
    [int]$MaxTokens = 768,
    [int]$CommandMaxTokens = 2048,
    [int]$TimeoutSec = 180,
    [int]$MaxRetriesPerRoute = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VxnRoot)) {
    $VxnRoot = Join-Path $ProjectRoot 'VXN'
}

$busRoot = Join-Path $VxnRoot 'runtime\load_balancing_bus'
$routePlanPath = Join-Path $busRoot 'routes\CURRENT_BUS_ROUTE_PLAN.json'

$schedulerPlanPath = Join-Path $VxnRoot 'runtime\scheduler\plans\CURRENT_SCHEDULE_PLAN.json'
$formationPath = Join-Path $VxnRoot 'runtime\rpg\formations\CURRENT_FORMATION_PLAN.json'

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runId = "VXN-SCHEDULED-BUS-EXEC-$stamp"
$runRoot = Join-Path $VxnRoot "experiments\formation_executor\$runId"

$null = New-Item -ItemType Directory -Force -Path $runRoot

function Banner([string]$Text) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Magenta
    Write-Host " $Text" -ForegroundColor Magenta
    Write-Host '============================================================' -ForegroundColor Magenta
}

function Write-Json([string]$Path,$Object) {
    $parent = Split-Path -Parent $Path
    if ($parent) { $null = New-Item -ItemType Directory -Force -Path $parent }

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

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }

        try {
            if ($Object.ContainsKey($Name)) { return $Object[$Name] }
        }
        catch {}

        return $Default
    }

    $p = $Object.PSObject.Properties[$Name]

    if ($null -eq $p -or $null -eq $p.Value) {
        return $Default
    }

    return $p.Value
}

function Clean-Text([string]$Content,[string]$Reasoning) {
    $t = $Content

    if ([string]::IsNullOrWhiteSpace($t)) {
        $t = $Reasoning
    }

    if ([string]::IsNullOrWhiteSpace($t)) {
        return ''
    }

    $t = [regex]::Replace($t,'(?is)<think>.*?</think>','').Trim()
    $t = $t -replace '^```(?:json|text)?\s*',''
    $t = $t -replace '\s*```$',''

    return $t.Trim()
}

function Find-JsonObject([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    try {
        $o = $Text | ConvertFrom-Json -AsHashtable
        if ($o -is [System.Collections.IDictionary]) {
            return $o
        }
    }
    catch {}

    $start = $Text.IndexOf('{')
    if ($start -lt 0) {
        return $null
    }

    $depth = 0
    $inString = $false
    $escape = $false

    for ($i=$start; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]

        if ($inString) {
            if ($escape) {
                $escape = $false
                continue
            }

            if ($c -eq '\') {
                $escape = $true
                continue
            }

            if ($c -eq '"') {
                $inString = $false
            }

            continue
        }

        if ($c -eq '"') {
            $inString = $true
            continue
        }

        if ($c -eq '{') {
            $depth++
        }
        elseif ($c -eq '}') {
            $depth--

            if ($depth -eq 0) {
                $candidate = $Text.Substring($start,$i-$start+1)

                try {
                    return $candidate | ConvertFrom-Json -AsHashtable
                }
                catch {
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

        if ($Map -is [System.Collections.IDictionary]) {
            if ($Map.Contains($f)) {
                $ok = $true
            }
            else {
                try {
                    if ($Map.ContainsKey($f)) {
                        $ok = $true
                    }
                }
                catch {}
            }
        }

        if ($ok) {
            $present++
        }
        else {
            $missing += $f
        }
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

    return [pscustomobject]@{
        Score=[math]::Round($score,3)
        Green=($score -ge 0.90 -and $missing.Count -eq 0)
        Missing=$missing
    }
}

function Invoke-Model {
    param(
        [string]$Model,
        [string]$System,
        [string]$Prompt,
        [int]$TokenLimit=$CommandMaxTokens,
        [bool]$PreferJsonMode=$true
    )

    $body = @{
        model=$Model
        messages=@(
            @{role='system'; content=$System},
            @{role='user'; content=$Prompt}
        )
        temperature=0.0
        max_tokens=$TokenLimit
        stream=$false
    }

    if ($PreferJsonMode) {
        $body['response_format'] = @{
            type='json_object'
        }
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
        }
    }
    catch {
        $sw.Stop()

        $statusCode = 0
        try {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        catch {}

        # Some OpenAI-compatible runtimes/models may reject response_format.
        if ($PreferJsonMode) {
            return Invoke-Model `
                -Model $Model `
                -System $System `
                -Prompt $Prompt `
                -TokenLimit $TokenLimit `
                -PreferJsonMode $false
        }

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
        }
    }
}

function Invoke-LaneWave {
    param(
        [array]$LaneAssignments,
        [string]$MissionClass
    )

    $jobs = @()

    foreach ($lane in $LaneAssignments) {
        $task = Get-Prop $lane 'task' $null

        if ($null -eq $task) {
            continue
        }

        $role = [string](Get-Prop $task 'role' 'Agent')
        $model = [string](Get-Prop $lane 'model' (Get-Prop $task 'model' ''))
        $laneId = [string](Get-Prop $lane 'lane_id' '')
        $runtime = [string](Get-Prop $lane 'runtime' 'LM_STUDIO')
        $assignmentStatus = [string](Get-Prop $task 'assignment_status' 'EXPERIENCED')

        if ($runtime -ne 'LM_STUDIO') {
            $jobs += [pscustomobject]@{
                LaneId=$laneId
                Role=$role
                Model=$model
                AssignmentStatus=$assignmentStatus
                Success=$false
                StatusCode=0
                Content=''
                LatencyMs=0
                Error="Unsupported runtime target: $runtime"
                PromptTokens=$null
                CompletionTokens=$null
            }

            continue
        }

        $jobs += Start-ThreadJob `
            -Name "$laneId-$role" `
            -ArgumentList @(
                $laneId,
                $role,
                $model,
                $assignmentStatus,
                $MissionClass,
                $MaxTokens,
                $TimeoutSec
            ) `
            -ScriptBlock {
                param(
                    $LaneId,
                    $Role,
                    $Model,
                    $AssignmentStatus,
                    $MissionClass,
                    $MaxTokensLocal,
                    $TimeoutSecLocal
                )

                $system = @"
You are a member of a VXN ARD scheduled formation.

LANE: $LaneId
ROLE: $Role
MISSION CLASS: $MissionClass
ASSIGNMENT STATUS: $AssignmentStatus

RULES:
- Candidate reasoning only.
- Never claim execution.
- Preserve unrelated state.
- Separate facts from assumptions.
- Identify risks and unknowns.
- Human approval is required before mutation.
- Do not widen scope.
- Return concise role-specific analysis.
"@

                $prompt = @"
Analyze this mission conservatively.

Mission Class: $MissionClass

Return only the role-specific contribution needed by the command integrator.
"@

                $body = @{
                    model=$Model
                    messages=@(
                        @{role='system'; content=$system},
                        @{role='user'; content=$prompt}
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

                    return [pscustomobject]@{
                        LaneId=$LaneId
                        Role=$Role
                        Model=$Model
                        AssignmentStatus=$AssignmentStatus
                        Success=$true
                        StatusCode=200
                        Content=$content
                        LatencyMs=$sw.ElapsedMilliseconds
                        Error=''
                        PromptTokens=$raw.usage.prompt_tokens
                        CompletionTokens=$raw.usage.completion_tokens
                    }
                }
                catch {
                    $sw.Stop()

                    $statusCode = 0
                    try {
                        $statusCode = [int]$_.Exception.Response.StatusCode
                    }
                    catch {}

                    return [pscustomobject]@{
                        LaneId=$LaneId
                        Role=$Role
                        Model=$Model
                        AssignmentStatus=$AssignmentStatus
                        Success=$false
                        StatusCode=$statusCode
                        Content=''
                        LatencyMs=$sw.ElapsedMilliseconds
                        Error=$_.Exception.Message
                        PromptTokens=$null
                        CompletionTokens=$null
                    }
                }
            }
    }

    $threadJobs = @($jobs | Where-Object { $_ -is [System.Management.Automation.Job] })
    $immediate = @($jobs | Where-Object { $_ -isnot [System.Management.Automation.Job] })

    if ($threadJobs.Count -gt 0) {
        $null = Wait-Job -Job $threadJobs
    }

    $results = @()

    foreach ($j in $threadJobs) {
        $results += Receive-Job -Job $j
        Remove-Job -Job $j -Force
    }

    $results += $immediate

    return @($results)
}

Banner 'VERTEX — SCHEDULED BUS EXECUTOR V0.1.1'

$routePlan = Read-JsonSafe $routePlanPath
$schedulerPlan = Read-JsonSafe $schedulerPlanPath
$formation = Read-JsonSafe $formationPath

if ($null -eq $routePlan) {
    throw "Bus Route Plan not found: $routePlanPath"
}

$busId = [string](Get-Prop $routePlan 'bus_id' 'UNKNOWN')
$scheduleId = [string](Get-Prop $routePlan 'schedule_id' 'UNKNOWN')
$missionClass = [string](Get-Prop $routePlan 'mission_class' 'GENERAL')
$routes = @(Get-Prop $routePlan 'routes' @())

$commandRoute = Get-Prop $routePlan 'command_route' $null
$commandModel = [string](Get-Prop $commandRoute 'model' '')
$capacity = Get-Prop $routePlan 'capacity_contract' $null

$initialWidth = [int](Get-Prop $capacity 'initial_width' 1)
$minimumWidth = [int](Get-Prop $capacity 'minimum_width' 1)

$formationId = if ($null -ne $formation) {
    [string](Get-Prop $formation 'formation_id' '')
}
else {
    ''
}

Write-Host "Run ID        : $runId"
Write-Host "Bus ID        : $busId"
Write-Host "Schedule ID   : $scheduleId"
Write-Host "Formation ID  : $formationId"
Write-Host "Mission Class : $missionClass"
Write-Host "Routes        : $($routes.Count)"
Write-Host "Initial Width : $initialWidth"
Write-Host "Command Model : $commandModel"

if (-not $Go) {
    Write-Host ''
    Write-Host 'GO SIGNAL : NOT PROVIDED' -ForegroundColor Yellow
    Write-Host 'NO LANES EXECUTED.'
    exit 0
}

Write-Host ''
Write-Host 'GO SIGNAL : RECEIVED' -ForegroundColor Green

$allResults = New-Object System.Collections.Generic.List[object]
$routeReceipts = New-Object System.Collections.Generic.List[object]

$currentWidth = [math]::Max($minimumWidth,$initialWidth)
$lastStableWidth = 0

Write-Host ''
Write-Host '[1/5] FIELD ROUTES' -ForegroundColor Cyan

foreach ($route in ($routes | Sort-Object { [int](Get-Prop $_ 'wave' 0) })) {
    $routeId = [string](Get-Prop $route 'route_id' '')
    $wave = [int](Get-Prop $route 'wave' 0)
    $lanes = @(Get-Prop $route 'lanes' @())

    $pending = New-Object System.Collections.Generic.List[object]

    foreach ($lane in $lanes) {
        $task = Get-Prop $lane 'task' $null
        if ($null -ne $task) {
            $pending.Add($lane)
        }
    }

    Write-Host ''
    Write-Host "  >>> $routeId / WAVE $wave" -ForegroundColor Cyan

    $attempt = 0

    while ($pending.Count -gt 0 -and $attempt -lt $MaxRetriesPerRoute) {
        $attempt++

        $effectiveWidth = [math]::Min($currentWidth,$pending.Count)

        $batch = @()

        for ($i=0; $i -lt $effectiveWidth; $i++) {
            $batch += $pending[0]
            $pending.RemoveAt(0)
        }

        Write-Host "      Attempt : $attempt"
        Write-Host "      Width   : $effectiveWidth"
        Write-Host "      Roles   : $(($batch | ForEach-Object { Get-Prop (Get-Prop $_ 'task' $null) 'role' '' }) -join ', ')"

        $results = @(Invoke-LaneWave `
            -LaneAssignments $batch `
            -MissionClass $missionClass)

        $success = @($results | Where-Object { $_.Success })
        $failed = @($results | Where-Object { -not $_.Success })
        $http500 = @($failed | Where-Object { $_.StatusCode -eq 500 })

        foreach ($r in $results) {
            if ($r.Success) {
                Write-Host "      RETURN : $($r.LaneId) $($r.Role) latency=$($r.LatencyMs)ms"
                $allResults.Add($r)
            }
            else {
                Write-Host "      ERROR  : $($r.LaneId) $($r.Role) status=$($r.StatusCode) $($r.Error)" -ForegroundColor Red
            }
        }

        $routeReceipts.Add([pscustomobject][ordered]@{
            route_id=$routeId
            wave=$wave
            attempt=$attempt
            width=$effectiveWidth
            success_count=$success.Count
            failure_count=$failed.Count
            http500_count=$http500.Count
        })

        if ($failed.Count -eq 0) {
            # A smaller final wave must not downgrade proven capacity.
            $lastStableWidth = [math]::Max($lastStableWidth,$effectiveWidth)
            continue
        }

        if ($http500.Count -gt 0 -and $currentWidth -gt $minimumWidth) {
            $oldWidth = $currentWidth
            $currentWidth--

            Write-Host "      BACKOFF: width $oldWidth -> $currentWidth" -ForegroundColor Yellow
        }

        foreach ($f in $failed) {
            $originalLane = $batch |
                Where-Object {
                    [string](Get-Prop $_ 'lane_id' '') -eq $f.LaneId
                } |
                Select-Object -First 1

            if ($null -ne $originalLane) {
                $pending.Add($originalLane)
            }
        }
    }

    if ($pending.Count -gt 0) {
        throw "Route $routeId exhausted retry budget with $($pending.Count) tasks unresolved."
    }
}

Write-Json (Join-Path $runRoot 'SCHEDULED_BUS_FIELD_RESULTS.json') @($allResults.ToArray())
Write-Json (Join-Path $runRoot 'SCHEDULED_BUS_ROUTE_RECEIPTS.json') @($routeReceipts.ToArray())

Write-Host ''
Write-Host '[2/5] COMMAND INTEGRATION' -ForegroundColor Cyan

$bundle = ''

foreach ($r in $allResults) {
    $bundle += @"

=== ROLE: $($r.Role) ===
LANE: $($r.LaneId)
MODEL: $($r.Model)
ASSIGNMENT: $($r.AssignmentStatus)

$($r.Content)

"@
}

$integratorSystem = @'
You are the VXN ARD Command Integrator.

Do not output chain-of-thought.
Do not explain your reasoning.
Return exactly one JSON object and nothing else.

Synthesize the field outputs conservatively.
Resolve contradictions.
Prefer explicit evidence.
Preserve unrelated state.
Do not widen scope.
Do not claim execution.

Required JSON keys:
status, intent, facts, assumptions, allowed_scope, locked_scope,
candidate_actions, risks, unknowns, requires_human_gate

Schema:
{
  "status":"READY|HOLD|REJECT",
  "intent":"short string",
  "facts":["short strings"],
  "assumptions":["short strings"],
  "allowed_scope":["short strings"],
  "locked_scope":["short strings"],
  "candidate_actions":["short strings"],
  "risks":["short strings"],
  "unknowns":["short strings"],
  "requires_human_gate":true
}
'@

$integrationPrompt = @"
MISSION CLASS:
$missionClass

FIELD OUTPUTS:
$bundle
"@

$integrationCall = Invoke-Model `
    -Model $commandModel `
    -System $integratorSystem `
    -Prompt $integrationPrompt `
    -TokenLimit $CommandMaxTokens

$integrationText = Clean-Text `
    -Content $integrationCall.Content `
    -Reasoning $integrationCall.Reasoning

$integrationMap = Find-JsonObject $integrationText
$integrationScore = Score-Result $integrationMap

Write-Json (Join-Path $runRoot 'COMMAND_PRIMARY_DIAGNOSTIC.json') ([ordered]@{
    model=$commandModel
    success=$integrationCall.Success
    status_code=$integrationCall.StatusCode
    latency_ms=$integrationCall.LatencyMs
    prompt_tokens=$integrationCall.PromptTokens
    completion_tokens=$integrationCall.CompletionTokens
    finish_reason=$integrationCall.FinishReason
    content=$integrationCall.Content
    reasoning=$integrationCall.Reasoning
    cleaned_text=$integrationText
    json_found=($null -ne $integrationMap)
    score=$integrationScore.Score
    green=$integrationScore.Green
})

Write-Host "  Model      : $commandModel"
Write-Host "  Tokens     : prompt=$($integrationCall.PromptTokens) completion=$($integrationCall.CompletionTokens)"
Write-Host "  Finish     : $($integrationCall.FinishReason)"
Write-Host "  JSON Found : $($null -ne $integrationMap)"
Write-Host "  Score      : $($integrationScore.Score)"
Write-Host "  Green      : $($integrationScore.Green)"

Set-Content `
    -LiteralPath (Join-Path $runRoot 'SCHEDULED_BUS_INTEGRATED_TEXT.txt') `
    -Value $integrationText `
    -Encoding UTF8

if ($null -ne $integrationMap) {
    Write-Json `
        (Join-Path $runRoot 'SCHEDULED_BUS_INTEGRATED_RESULT.json') `
        $integrationMap
}

Write-Host ''
Write-Host '[3/5] ESCALATION' -ForegroundColor Cyan

$finalMap = $integrationMap
$finalScore = $integrationScore
$finalModel = $commandModel
$escalationUsed = $false

if (-not $integrationScore.Green) {
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
        $models |
        Where-Object { $_ -match '(?i)(12|13|14)b' } |
        Select-Object -First 1

        $models |
        Where-Object { $_ -match '(?i)(30|32|34)b' } |
        Select-Object -First 1
    ) | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and
        $_ -ne $commandModel
    }

    foreach ($model in $fallbacks) {
        Write-Host "  ESCALATE -> $model" -ForegroundColor Yellow

        $review = Invoke-Model `
            -Model $model `
            -System $integratorSystem `
            -Prompt $integrationPrompt `
            -TokenLimit $CommandMaxTokens

        $reviewText = Clean-Text `
            -Content $review.Content `
            -Reasoning $review.Reasoning

        $reviewMap = Find-JsonObject $reviewText
        $reviewScore = Score-Result $reviewMap

        $safeModelName = ($model -replace '[^A-Za-z0-9._-]','_')
        Write-Json (Join-Path $runRoot "COMMAND_ESCALATION_$safeModelName.json") ([ordered]@{
            model=$model
            success=$review.Success
            status_code=$review.StatusCode
            latency_ms=$review.LatencyMs
            prompt_tokens=$review.PromptTokens
            completion_tokens=$review.CompletionTokens
            finish_reason=$review.FinishReason
            content=$review.Content
            reasoning=$review.Reasoning
            cleaned_text=$reviewText
            json_found=($null -ne $reviewMap)
            score=$reviewScore.Score
            green=$reviewScore.Green
        })

        $escalationUsed = $true
        $finalMap = $reviewMap
        $finalScore = $reviewScore
        $finalModel = $model

        Write-Host "  Tokens     : prompt=$($review.PromptTokens) completion=$($review.CompletionTokens)"
        Write-Host "  Finish     : $($review.FinishReason)"
        Write-Host "  JSON Found : $($null -ne $reviewMap)"
        Write-Host "  Score      : $($reviewScore.Score)"
        Write-Host "  Green      : $($reviewScore.Green)"

        if ($reviewScore.Green) {
            break
        }
    }
}
else {
    Write-Host '  NOT REQUIRED' -ForegroundColor Green
}

if ($lastStableWidth -le 0) {
    $lastStableWidth = [math]::Max($minimumWidth,$currentWidth)
}

Write-Host ''
Write-Host '[4/5] FORMATION-COMPATIBLE RECEIPT' -ForegroundColor Cyan

$formationRoles = @()

if ($null -ne $formation) {
    $formationParty = Get-Prop $formation 'party' $null
    $formationRoles = @(Get-Prop $formationParty 'roles' @())
}

$rookieResults = @()

foreach ($r in $allResults) {
    if ($r.AssignmentStatus -eq 'TRIAL_ASSIGNMENT') {
        $rookieResults += [ordered]@{
            role=$r.Role
            model=$r.Model
            success=$r.Success
            latency_ms=$r.LatencyMs
            status='TRIAL_COMPLETED'
        }
    }
}

$status = if ($finalScore.Green) { 'GREEN' } else { 'NOT_GREEN' }

$receipt = [ordered]@{
    schema='vertex.world.ard.formation-execution.v1.2'
    run_id=$runId
    formation_id=$formationId
    mission_class=$missionClass
    completed_at=(Get-Date).ToString('o')
    status=$status

    scheduler=[ordered]@{
        schedule_id=$scheduleId
        bus_id=$busId
        initial_width=$initialWidth
        final_width=$currentWidth
        last_stable_width=$lastStableWidth
        route_receipts=@($routeReceipts.ToArray())
    }

    party=[ordered]@{
        logical_size=$formationRoles.Count
        planned_width=$initialWidth
        stable_width=$lastStableWidth
        results=@(
            $allResults |
            ForEach-Object {
                [ordered]@{
                    Role=$_.Role
                    Model=$_.Model
                    AssignmentStatus=$_.AssignmentStatus
                    Success=$_.Success
                    StatusCode=$_.StatusCode
                    Content=$_.Content
                    LatencyMs=$_.LatencyMs
                    PromptTokens=$_.PromptTokens
                    CompletionTokens=$_.CompletionTokens
                }
            }
        )
    }

    rookies=$rookieResults

    integrator=[ordered]@{
        model=$commandModel
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

$receiptPath = Join-Path $runRoot 'VERTEX_ARD_FORMATION_EXECUTION_RECEIPT.json'
Write-Json $receiptPath $receipt

Write-Host "  Status       : $status"
Write-Host "  Stable Width : $lastStableWidth"
Write-Host "  Receipt      : $receiptPath"

Write-Host ''
Write-Host '[5/5] LEARNING LOOP HANDOFF' -ForegroundColor Cyan
Write-Host '  Receipt is ready for existing Formation Evidence RPG Ingestion Bridge.'

Banner 'VERTEX — SCHEDULED BUS EXECUTION COMPLETE'

Write-Host "Mission          : $missionClass"
Write-Host "Field Results    : $($allResults.Count)"
Write-Host "Initial Width    : $initialWidth"
Write-Host "Final Width      : $currentWidth"
Write-Host "Stable Width     : $lastStableWidth"
Write-Host "Command Model    : $commandModel"
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
    Write-Host 'SCHEDULED BUS MISSION CLEAR.' -ForegroundColor Green
}

Write-Host '轟。' -ForegroundColor Green
