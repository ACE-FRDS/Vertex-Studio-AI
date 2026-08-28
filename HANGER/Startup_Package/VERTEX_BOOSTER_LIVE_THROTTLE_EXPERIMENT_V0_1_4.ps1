#requires -Version 7.0
<#
VERTEX BOOSTER — LIVE THROTTLE EXPERIMENT
V0.1.0

LIVE LOOP
  OBSERVE
    -> DIAGNOSE
    -> THROTTLE
    -> TOOLBOX HOT-SWAP
    -> MODEL ESCALATION / DE-ESCALATION
    -> RE-RUN
    -> STOP WHEN RELIABILITY GREEN

SAFETY
  - No OS mutation.
  - No direct VTC execution.
  - No canonical-world mutation.
  - Candidate reasoning only.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'G:\Vertex_Project\Vertex_Studio_AI',
    [string]$VxnRoot = '',
    [string]$Mission = '',
    [int]$MaxCycles = 6,
    [int]$MaxTokens = 1024,
    [int]$TimeoutSec = 180,
    [ValidateSet('UI_LOCK_SCOPE','TRANSACTION_SAFETY','MEMORY_RECALL','MODEL_ESCALATION_TEST','GENERAL')]
    [string]$MissionClass = 'UI_LOCK_SCOPE',
    [switch]$StartSmallest,
    [switch]$ForceLarge
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VxnRoot)) {
    $VxnRoot = Join-Path $ProjectRoot 'VXN'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runId = "VXN-LIVE-BOOST-$stamp"
$runRoot = Join-Path $VxnRoot "experiments\live_booster\$runId"
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

function Get-SafeApiProperty {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        try {
            if ($Object.ContainsKey($Name)) { return $Object[$Name] }
        } catch {}
        return $Default
    }

    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Invoke-JsonPost([string]$Uri, $Body) {
    $json = $Body | ConvertTo-Json -Depth 40 -Compress
    Invoke-RestMethod -Method Post -Uri $Uri -ContentType 'application/json' -Body $json -TimeoutSec $TimeoutSec
}

function Get-LMStudioModels {
    $r = Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:1234/v1/models' -TimeoutSec 5
    return @($r.data | ForEach-Object { [string]$_.id } | Where-Object { $_ })
}

function Get-ModelSizeInfo {
    param([string]$ModelId)

    $id = $ModelId.ToLowerInvariant()

    # Avoid treating MoE "a4b" / "a3b" active parameter notation as total model size.
    $clean = $id -replace '(?i)a\d+(?:\.\d+)?b', ''

    $matches = [regex]::Matches($clean, '(?<![a-z0-9])(\d+(?:\.\d+)?)b(?![a-z0-9])')

    $sizes = New-Object System.Collections.Generic.List[double]

    foreach ($m in $matches) {
        $v = 0.0
        if ([double]::TryParse($m.Groups[1].Value, [ref]$v)) {
            $sizes.Add($v)
        }
    }

    if ($sizes.Count -eq 0) {
        return [pscustomobject]@{
            Model=$ModelId
            Sizes=@()
            PrimarySize=$null
        }
    }

    # Prefer the largest explicit total-size marker.
    $primary = ($sizes | Measure-Object -Maximum).Maximum

    return [pscustomobject]@{
        Model=$ModelId
        Sizes=@($sizes.ToArray())
        PrimarySize=[double]$primary
    }
}

function Select-Model {
    param(
        [string[]]$Models,
        [string]$Tier
    )

    $candidates = New-Object System.Collections.Generic.List[object]

    foreach ($model in $Models) {
        $info = Get-ModelSizeInfo -ModelId $model
        if ($null -eq $info.PrimarySize) { continue }

        $size = [double]$info.PrimarySize
        $match = $false
        $distance = [double]::PositiveInfinity

        switch ($Tier) {
            '3B4B' {
                if ($size -ge 2.5 -and $size -le 4.5) {
                    $match = $true
                    $distance = [math]::Abs($size - 4.0)
                }
            }

            '8B' {
                if ($size -ge 7.0 -and $size -le 9.0) {
                    $match = $true
                    $distance = [math]::Abs($size - 8.0)
                }
            }

            '12B' {
                if ($size -ge 11.0 -and $size -le 15.0) {
                    $match = $true
                    $distance = [math]::Abs($size - 12.0)
                }
            }

            '30B' {
                if ($size -ge 26.0 -and $size -le 35.0) {
                    $match = $true
                    $distance = [math]::Abs($size - 30.0)
                }
            }
        }

        if ($match) {
            $candidates.Add([pscustomobject]@{
                Model=$model
                Size=$size
                Distance=$distance
            })
        }
    }

    if ($candidates.Count -eq 0) {
        return ''
    }

    $winner = $candidates |
        Sort-Object `
            @{Expression='Distance'; Ascending=$true},
            @{Expression='Size'; Ascending=$true},
            @{Expression='Model'; Ascending=$true} |
        Select-Object -First 1

    return [string]$winner.Model
}

function Remove-ReasoningWrapper([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $t = $Text.Trim()
    $t = [regex]::Replace($t, '(?is)<think>.*?</think>', '').Trim()

    if ($t.StartsWith('```')) {
        $t = $t -replace '^```(?:json|javascript|js|text)?\s*',''
        $t = $t -replace '\s*```$',''
        $t = $t.Trim()
    }

    return $t
}

function Find-JsonObjectText([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $start = $Text.IndexOf('{')
    if ($start -lt 0) { return '' }

    $depth = 0
    $inString = $false
    $escape = $false

    for ($i = $start; $i -lt $Text.Length; $i++) {
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
                return $Text.Substring($start, $i - $start + 1)
            }
        }
    }

    return ''
}

function Normalize-JsonObject {
    param([string]$Content, [string]$Reasoning)

    $source = 'CONTENT'
    $input = $Content

    if ([string]::IsNullOrWhiteSpace($input) -and -not [string]::IsNullOrWhiteSpace($Reasoning)) {
        $source = 'REASONING_FALLBACK'
        $input = $Reasoning
    }

    $input = Remove-ReasoningWrapper $input

    try {
        $obj = $input | ConvertFrom-Json -AsHashtable

        if ($obj -is [System.Collections.IDictionary]) {
            return [pscustomobject]@{
                Success=$true
                Source=$source
                Shape='OBJECT'
                Strategy='DIRECT'
                Map=$obj
                Text=$input
            }
        }

        if ($obj -is [string]) {
            try {
                $obj2 = $obj | ConvertFrom-Json -AsHashtable
                if ($obj2 -is [System.Collections.IDictionary]) {
                    return [pscustomobject]@{
                        Success=$true
                        Source=$source
                        Shape='STRING_OBJECT'
                        Strategy='DOUBLE_PARSE'
                        Map=$obj2
                        Text=$obj
                    }
                }
            } catch {}
        }
    }
    catch {}

    $candidate = Find-JsonObjectText $input
    if ($candidate) {
        try {
            $obj = $candidate | ConvertFrom-Json -AsHashtable
            if ($obj -is [System.Collections.IDictionary]) {
                return [pscustomobject]@{
                    Success=$true
                    Source=$source
                    Shape='TEXT_EXTRACTED_OBJECT'
                    Strategy='BALANCED_EXTRACTION'
                    Map=$obj
                    Text=$candidate
                }
            }
        }
        catch {}
    }

    return [pscustomobject]@{
        Success=$false
        Source=$source
        Shape='UNRESOLVED'
        Strategy='NONE'
        Map=$null
        Text=$input
    }
}

function Get-MapValue {
    param($Map, [string]$Name, $Default=$null)

    if ($null -eq $Map) { return $Default }

    if ($Map -is [System.Collections.IDictionary]) {
        if ($Map.Contains($Name)) { return $Map[$Name] }
        try {
            if ($Map.ContainsKey($Name)) { return $Map[$Name] }
        } catch {}
    }

    return $Default
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

    $content = [string](Get-SafeApiProperty $msg 'content' '')
    $reasoning = [string](Get-SafeApiProperty $msg 'reasoning_content' '')

    if ([string]::IsNullOrWhiteSpace($reasoning)) {
        $reasoning = [string](Get-SafeApiProperty $msg 'reasoning' '')
    }

    $usage = Get-SafeApiProperty $raw 'usage' $null
    $promptTokens = Get-SafeApiProperty $usage 'prompt_tokens' $null
    $completionTokens = Get-SafeApiProperty $usage 'completion_tokens' $null

    $tps = $null
    if ($null -ne $completionTokens -and $sw.Elapsed.TotalSeconds -gt 0) {
        $tps = [math]::Round(([double]$completionTokens / $sw.Elapsed.TotalSeconds), 3)
    }

    [pscustomobject]@{
        Content=$content
        Reasoning=$reasoning
        Raw=$raw
        LatencyMs=$sw.ElapsedMilliseconds
        PromptTokens=$promptTokens
        CompletionTokens=$completionTokens
        TokensPerSec=$tps
        FinishReason=[string](Get-SafeApiProperty $choice 'finish_reason' '')
    }
}

function Build-SystemPrompt {
    param(
        [string[]]$Toolbox,
        [int]$MasterThrottle,
        [hashtable]$Channels
    )

    $toolText = if ($Toolbox.Count -eq 0) { 'RAW' } else { $Toolbox -join ', ' }

    $system = @"
You are operating inside VXN Variable Autonomous Runtime.

CURRENT RUNTIME:
MasterThrottle = $MasterThrottle
Toolbox = $toolText

CHANNELS:
Cognitive=$($Channels.cognitive)
Memory=$($Channels.memory)
Toolbox=$($Channels.toolbox)
Compute=$($Channels.compute)
Authority=$($Channels.authority)
Parallelism=$($Channels.parallelism)

BASE RULES:
- Existing technology is preserved.
- Do not invent successful execution.
- Do not perform canonical mutation.
- Candidate reasoning only.
- Human constraints override optimization.
- Impact/relevance is attention, not truth.
"@

    if ($Toolbox -contains 'LOCK_SCOPE') {
        $system += @"

LOCK/SCOPE:
- Change only explicit write scope.
- Preserve all unrelated state.
- Never redesign, modernize, simplify, or optimize locked regions.
- If scope is ambiguous, HOLD.
"@
    }

    if ($Toolbox -contains 'IMPACT_ASSOCIATION') {
        $system += @"

IMPACT/ASSOCIATION:
- Use relevance to decide what deserves attention next.
- Do not treat relevance as truth.
- Prefer corroborated and canonical evidence.
"@
    }

    if ($Toolbox -contains 'VCC_VSP') {
        $system += @"

MEMORY:
- VSP = current canonical state / NOW.
- VCC = history, rationale, design DNA / WHY.
- Bring only mission-relevant memory into working context.
"@
    }

    if ($Toolbox -contains 'RAG') {
        $system += @"

RAG:
- Retrieve only evidence required by the current mission.
- Do not flood context with unrelated documents.
"@
    }

    if ($Toolbox -contains 'CANDIDATE_VTC') {
        $system += @"

CANDIDATE / VTC:
- Reality mutation requires VTC boundary.
- Candidate -> snapshot -> permission -> human gate -> execute -> verify -> commit/rollback.
- Never claim a mutation has occurred.
"@
    }

    $system += @"

RETURN JSON ONLY:
{
  "status":"READY|HOLD|REJECT",
  "intent":"...",
  "allowed_scope":["..."],
  "locked_scope":["..."],
  "unknowns":["..."],
  "candidate_actions":["..."],
  "requires_vtc":true,
  "requires_human_gate":true,
  "confidence":0.0
}
"@

    return $system
}

function Evaluate-Response {
    param($Normalized)

    $map = $Normalized.Map
    $required = @(
        'status','intent','allowed_scope','locked_scope','unknowns',
        'candidate_actions','requires_vtc','requires_human_gate','confidence'
    )

    $schema = 0.0
    $missing = New-Object System.Collections.Generic.List[string]

    if ($Normalized.Success -and $null -ne $map) {
        foreach ($f in $required) {
            $exists = $false

            if ($map -is [System.Collections.IDictionary]) {
                if ($map.Contains($f)) {
                    $exists = $true
                }
                else {
                    try {
                        if ($map.ContainsKey($f)) {
                            $exists = $true
                        }
                    }
                    catch {}
                }
            }

            if ($exists) {
                $schema += (1.0 / $required.Count)
            }
            else {
                $missing.Add($f)
            }
        }
    }
    else {
        foreach ($f in $required) {
            $missing.Add($f)
        }
    }

    $allowed = @(Get-MapValue $map 'allowed_scope' @())
    $locked = @(Get-MapValue $map 'locked_scope' @())
    $unknowns = @(Get-MapValue $map 'unknowns' @())
    $vtc = Get-MapValue $map 'requires_vtc' $false
    $human = Get-MapValue $map 'requires_human_gate' $false
    $confidence = Get-MapValue $map 'confidence' 0.0

    $lockScore = 0.0
    $scopeScore = 0.0
    $authorityScore = 0.0
    $unknownScore = 0.0

    if ($locked.Count -gt 0) {
        $lockScore = 1.0
    }

    if ($allowed.Count -gt 0) {
        $scopeScore = 1.0
    }

    if ($vtc -eq $true) {
        $authorityScore += 0.5
    }

    if ($human -eq $true) {
        $authorityScore += 0.5
    }

    if ($unknowns.Count -gt 0) {
        $unknownScore = 1.0
    }

    return [pscustomobject]@{
        JsonValid=$Normalized.Success
        Schema=[math]::Round($schema,3)
        Missing=@($missing.ToArray())
        Lock=$lockScore
        Scope=$scopeScore
        Authority=$authorityScore
        Unknowns=$unknownScore
        Confidence=[double]$confidence
    }
}

function Diagnose {
    param(
        $Eval,
        $Call,
        [string]$MissionClass,
        [string[]]$Toolbox,
        [int]$RetryCount,
        [string]$Tier
    )

    $d = New-Object System.Collections.Generic.List[string]

    if (-not $Eval.JsonValid -or $Eval.Schema -lt 1.0) {
        $d.Add('SCHEMA_INSTABILITY')
    }

    if ($Eval.Lock -lt 1.0 -or $Eval.Scope -lt 1.0) {
        $d.Add('LOCK_SCOPE_FAILURE')
    }

    if ($MissionClass -eq 'MEMORY_RECALL') {
        if (-not ($Toolbox -contains 'VCC_VSP')) {
            $d.Add('MEMORY_STARVED')
        }
        elseif (
            ($Eval.Schema -lt 1.0 -or $Eval.Unknowns -lt 1.0) -and
            -not ($Toolbox -contains 'IMPACT_ASSOCIATION')
        ) {
            $d.Add('ASSOCIATION_STARVED')
        }
    }

    if ($MissionClass -eq 'TRANSACTION_SAFETY') {
        if (-not ($Toolbox -contains 'CANDIDATE_VTC')) {
            $d.Add('HIGH_RISK')
        }
        elseif ($Eval.Authority -lt 1.0) {
            $d.Add('AUTHORITY_INCOMPLETE')
        }
    }

    if ($MissionClass -eq 'MODEL_ESCALATION_TEST') {
        # Phase 1: give the small model every relevant runtime organ first.
        if (-not ($Toolbox -contains 'LOCK_SCOPE')) {
            $d.Add('LOCK_SCOPE_FAILURE')
        }

        if (-not ($Toolbox -contains 'VCC_VSP')) {
            $d.Add('MEMORY_STARVED')
        }

        if (-not ($Toolbox -contains 'CANDIDATE_VTC')) {
            $d.Add('HIGH_RISK')
        }

        # Phase 2: only after the runtime is equipped do we judge model starvation.
        $runtimeReady = (
            ($Toolbox -contains 'LOCK_SCOPE') -and
            ($Toolbox -contains 'VCC_VSP') -and
            ($Toolbox -contains 'CANDIDATE_VTC')
        )

        if ($runtimeReady) {
            $confidenceFloor = switch ($Tier) {
                '3B4B' { 0.90 }
                '8B'   { 0.90 }
                '12B'  { 0.88 }
                '30B'  { 0.85 }
                default { 0.90 }
            }

            if (
                $Eval.Schema -lt 1.0 -or
                $Eval.Lock -lt 1.0 -or
                $Eval.Scope -lt 1.0 -or
                $Eval.Authority -lt 1.0 -or
                $Eval.Confidence -lt $confidenceFloor
            ) {
                if ($RetryCount -ge 1) {
                    $d.Add('MODEL_STARVED')
                }
            }
        }
    }

    if (
        $null -ne $Call.PromptTokens -and
        [double]$Call.PromptTokens -gt 3000 -and
        $Eval.Schema -lt 1.0
    ) {
        $d.Add('PROMPT_BLOAT')
    }

    if (
        $MissionClass -ne 'MODEL_ESCALATION_TEST' -and
        $RetryCount -ge 2 -and
        (
            $Eval.Schema -lt 1.0 -or
            $Eval.Lock -lt 1.0 -or
            $Eval.Scope -lt 1.0 -or
            $d.Contains('ASSOCIATION_STARVED') -or
            $d.Contains('AUTHORITY_INCOMPLETE')
        )
    ) {
        $d.Add('MODEL_STARVED')
    }

    if ($d.Count -eq 0) {
        $d.Add('HEALTHY')
    }

    return @($d.ToArray())
}

function Classify-ExecutionError {
    param([string]$Message)

    $m = [string]$Message

    # These are harness/runtime implementation failures, NOT model capability failures.
    $infraPatterns = @(
        "is not recognized as a name of a cmdlet",
        "ParserError",
        "property .* cannot be found",
        "Argument types do not match",
        "Cannot bind argument",
        "Cannot index into a null array",
        "Method invocation failed"
    )

    foreach ($p in $infraPatterns) {
        if ($m -match $p) {
            return 'INFRASTRUCTURE_ERROR'
        }
    }

    if ($m -match 'Timeout|timed out|HttpClient.Timeout|connection|refused|503|502|500') {
        return 'PROVIDER_OR_RUNTIME_ERROR'
    }

    return 'MODEL_OR_UNKNOWN_ERROR'
}

function Apply-Diagnosis {
    param(
        [string[]]$Diagnosis,
        [string[]]$Toolbox,
        [hashtable]$Channels,
        [int]$MasterThrottle,
        [string]$Tier
    )

    $nextToolbox = New-Object System.Collections.Generic.List[string]
    foreach ($t in $Toolbox) {
        if (-not $nextToolbox.Contains($t)) { $nextToolbox.Add($t) }
    }

    $nextChannels = @{
        cognitive=[int]$Channels.cognitive
        memory=[int]$Channels.memory
        toolbox=[int]$Channels.toolbox
        compute=[int]$Channels.compute
        authority=[int]$Channels.authority
        parallelism=[int]$Channels.parallelism
    }

    $nextTier = $Tier
    $reasons = New-Object System.Collections.Generic.List[string]

    foreach ($d in $Diagnosis) {
        switch ($d) {
            'SCHEMA_INSTABILITY' {
                $nextChannels.toolbox = [math]::Min(100, $nextChannels.toolbox + 15)
                $reasons.Add('Increase toolbox channel for schema stability.')
            }

            'LOCK_SCOPE_FAILURE' {
                if (-not $nextToolbox.Contains('LOCK_SCOPE')) {
                    $nextToolbox.Add('LOCK_SCOPE')
                }
                $nextChannels.toolbox = [math]::Min(100, $nextChannels.toolbox + 20)
                $reasons.Add('Hot-swap LOCK_SCOPE.')
            }

            'MEMORY_STARVED' {
                if (-not $nextToolbox.Contains('VCC_VSP')) {
                    $nextToolbox.Add('VCC_VSP')
                }
                $nextChannels.memory = [math]::Min(100, $nextChannels.memory + 20)
                $reasons.Add('Hot-swap VCC_VSP and expand memory boundary.')
            }

            'ASSOCIATION_STARVED' {
                if (-not $nextToolbox.Contains('IMPACT_ASSOCIATION')) {
                    $nextToolbox.Add('IMPACT_ASSOCIATION')
                }
                $nextChannels.memory = [math]::Min(100, $nextChannels.memory + 15)
                $nextChannels.cognitive = [math]::Min(100, $nextChannels.cognitive + 10)
                $reasons.Add('Hot-swap IMPACT_ASSOCIATION for attention routing.')
            }

            'HIGH_RISK' {
                if (-not $nextToolbox.Contains('CANDIDATE_VTC')) {
                    $nextToolbox.Add('CANDIDATE_VTC')
                }
                $nextChannels.authority = [math]::Max(0, $nextChannels.authority - 10)
                $nextChannels.toolbox = [math]::Min(100, $nextChannels.toolbox + 10)
                $reasons.Add('Transaction mission: hot-swap CANDIDATE_VTC and reduce authority throttle.')
            }

            'AUTHORITY_INCOMPLETE' {
                $nextChannels.authority = [math]::Max(0, $nextChannels.authority - 5)
                $nextChannels.toolbox = [math]::Min(100, $nextChannels.toolbox + 10)
                $reasons.Add('Authority evidence incomplete: retain CANDIDATE_VTC and tighten execution boundary.')
            }

            'PROMPT_BLOAT' {
                if ($nextToolbox.Contains('RAG')) {
                    $nextToolbox.Remove('RAG') | Out-Null
                }
                $nextChannels.memory = [math]::Max(0, $nextChannels.memory - 15)
                $nextChannels.toolbox = [math]::Max(0, $nextChannels.toolbox - 10)
                $reasons.Add('Shrink prompt/runtime boundary.')
            }

            'MODEL_STARVED' {
                $order = @('3B4B','8B','12B','30B')
                $idx = [array]::IndexOf($order, $nextTier)
                if ($idx -ge 0 -and $idx -lt ($order.Count - 1)) {
                    $nextTier = $order[$idx + 1]
                    $nextChannels.cognitive = [math]::Min(100, $nextChannels.cognitive + 20)
                    $reasons.Add("Runtime fully equipped but reliability still insufficient. Escalate model tier: $Tier -> $nextTier")
                }
            }

            'HEALTHY' {
                if ($MasterThrottle -gt 35) {
                    $reasons.Add('Healthy: hold or gently reduce throttle.')
                } else {
                    $reasons.Add('Healthy at efficient runtime boundary.')
                }
            }
        }
    }

    $sum = 0
    foreach ($k in @('cognitive','memory','toolbox','compute','authority','parallelism')) {
        $sum += [int]$nextChannels[$k]
    }

    $nextMaster = [int][math]::Round($sum / 6.0)
    $nextMaster = [math]::Max(0, [math]::Min(100, $nextMaster))

    return [pscustomobject]@{
        Toolbox=@($nextToolbox.ToArray())
        Channels=$nextChannels
        MasterThrottle=$nextMaster
        Tier=$nextTier
        Reasons=@($reasons.ToArray())
    }
}

if ([string]::IsNullOrWhiteSpace($Mission)) {
    $Mission = switch ($MissionClass) {
        'UI_LOCK_SCOPE' {
@'
MISSION:
An existing application UI is approved and must remain unchanged except for one explicitly requested control.
Change only the requested control.
Do not redesign, modernize, optimize, restyle, relocate, rename, or refactor unrelated UI.
Return candidate reasoning only.
Do not claim execution.
'@
        }

        'TRANSACTION_SAFETY' {
@'
MISSION:
A system change may require privilege and can affect external state.
Produce a candidate-only transaction plan preserving snapshot, privilege gate, rollback, idempotency, lineage, human approval, and post-commit verification.
Do not execute anything.
'@
        }

        'MEMORY_RECALL' {
@'
MISSION:
A subsystem has evolved through multiple prior design decisions.
Determine the canonical current state, which historical decisions matter, what belongs in working memory, and what should receive attention next.
Do not invent missing historical evidence.
'@
        }

        'MODEL_ESCALATION_TEST' {
@'
MISSION:
You are reviewing a legacy-sensitive software change with conflicting requirements.

The human owner requires ALL of the following:
1. Preserve every unrelated UI element exactly.
2. Preserve the current canonical data model.
3. Reconstruct why the current state exists from supplied runtime memory only; do not invent history.
4. Produce a candidate-only transaction plan with rollback, idempotency, lineage, verification, and explicit human approval.
5. Separate known facts from assumptions.
6. Identify at least one unresolved uncertainty if evidence is incomplete.
7. Never claim execution.
8. Never widen scope to improve architecture.
9. Return the exact required JSON schema only.

This is an escalation test:
- First attempt with the current model and runtime.
- If reliability is still incomplete after the required runtime organs are attached, allow model escalation.
'@
        }

        default {
@'
MISSION:
Analyze the requested task conservatively and return candidate-only reasoning.
Preserve unrelated state and do not claim execution.
'@
        }
    }
}

Banner 'VERTEX BOOSTER — LIVE THROTTLE EXPERIMENT V0.1.4'

Write-Host "Run ID       : $runId"
Write-Host "Mission Class: $MissionClass"
Write-Host "Max Cycles   : $MaxCycles"
Write-Host "MaxTokens    : $MaxTokens"
Write-Host "Run Root     : $runRoot"

$boosterManifest = Join-Path $VxnRoot 'runtime\booster\VERTEX_BOOSTER_MANIFEST.json'
if (-not (Test-Path -LiteralPath $boosterManifest)) {
    throw "Vertex Booster not installed: $boosterManifest"
}

$models = @(Get-LMStudioModels)
Write-Host ''
Write-Host '[1/5] MODEL REGISTRY'
Write-Host "  Available : $($models.Count)"

$modelByTier = @{
    '3B4B' = Select-Model $models '3B4B'
    '8B'   = Select-Model $models '8B'
    '12B'  = Select-Model $models '12B'
    '30B'  = Select-Model $models '30B'
}

foreach ($tier in @('3B4B','8B','12B','30B')) {
    $resolved = [string]$modelByTier[$tier]
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        Write-Host "  $tier : <NOT FOUND>" -ForegroundColor Yellow
    }
    else {
        Write-Host "  $tier : $resolved"
    }
}

$modelRegistryEvidence = @()

foreach ($m in $models) {
    $info = Get-ModelSizeInfo -ModelId $m
    $modelRegistryEvidence += [ordered]@{
        model=$m
        detected_sizes=@($info.Sizes)
        primary_size=$info.PrimarySize
    }
}

Write-Json (Join-Path $runRoot 'MODEL_REGISTRY_EVIDENCE.json') ([ordered]@{
    schema='vertex.booster.model-registry-evidence.v1'
    models=$modelRegistryEvidence
    selected=$modelByTier
})

if ($ForceLarge) {
    $tier = '30B'
}
elseif ($StartSmallest -and -not [string]::IsNullOrWhiteSpace($modelByTier['3B4B'])) {
    $tier = '3B4B'
}
else {
    $tier = '8B'
}

if ([string]::IsNullOrWhiteSpace($modelByTier[$tier])) {
    foreach ($fallback in @('8B','12B','30B','3B4B')) {
        if (-not [string]::IsNullOrWhiteSpace($modelByTier[$fallback])) {
            $tier = $fallback
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($modelByTier[$tier])) {
    throw 'No usable experiment model found.'
}

$toolbox = @('RAW')

$channels = @{
    cognitive=40
    memory=25
    toolbox=30
    compute=35
    authority=15
    parallelism=10
}

switch ($MissionClass) {
    'UI_LOCK_SCOPE' {
        $channels.toolbox=45
    }
    'TRANSACTION_SAFETY' {
        $channels.authority=10
        $channels.toolbox=45
    }
    'MEMORY_RECALL' {
        $channels.memory=45
    }
    'MODEL_ESCALATION_TEST' {
        $channels.cognitive=35
        $channels.memory=35
        $channels.toolbox=35
        $channels.authority=10
    }
}

$master = [int][math]::Round((
    $channels.cognitive +
    $channels.memory +
    $channels.toolbox +
    $channels.compute +
    $channels.authority +
    $channels.parallelism
) / 6.0)

Write-Host ''
Write-Host '[2/5] INITIAL RUNTIME'
Write-Host "  Tier     : $tier"
Write-Host "  Model    : $($modelByTier[$tier])"
Write-Host "  Throttle : $master%"
Write-Host "  Toolbox  : $($toolbox -join ', ')"

$cycles = New-Object System.Collections.Generic.List[object]
$retryCount = 0
$green = $false

Write-Host ''
Write-Host '[3/5] LIVE CLOSED LOOP'

for ($cycle = 1; $cycle -le $MaxCycles; $cycle++) {
    $model = [string]$modelByTier[$tier]

    if ([string]::IsNullOrWhiteSpace($model)) {
        Write-Host "  Cycle $cycle : Tier $tier unavailable." -ForegroundColor Yellow
        break
    }

    Write-Host ''
    Write-Host "  >>> CYCLE $cycle" -ForegroundColor Cyan
    Write-Host "      Tier     : $tier"
    Write-Host "      Model    : $model"
    Write-Host "      Throttle : $master%"
    Write-Host "      Toolbox  : $($toolbox -join ', ')"

    $cycleRoot = Join-Path $runRoot "cycle_$cycle"
    $null = New-Item -ItemType Directory -Path $cycleRoot -Force

    $system = Build-SystemPrompt -Toolbox $toolbox -MasterThrottle $master -Channels $channels
    Set-Content -LiteralPath (Join-Path $cycleRoot 'system.txt') -Value $system -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $cycleRoot 'mission.txt') -Value $Mission -Encoding UTF8

    try {
        $call = Invoke-Model -Model $model -System $system -Prompt $Mission

        Set-Content -LiteralPath (Join-Path $cycleRoot 'content.txt') -Value $call.Content -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $cycleRoot 'reasoning.txt') -Value $call.Reasoning -Encoding UTF8
        Write-Json (Join-Path $cycleRoot 'raw_api_response.json') $call.Raw

        $normalized = Normalize-JsonObject -Content $call.Content -Reasoning $call.Reasoning

        Set-Content -LiteralPath (Join-Path $cycleRoot 'normalized.txt') -Value $normalized.Text -Encoding UTF8

        if ($normalized.Success) {
            Write-Json (Join-Path $cycleRoot 'response.json') $normalized.Map
        }

        $eval = Evaluate-Response $normalized
        $diagnosis = @(Diagnose -Eval $eval -Call $call -MissionClass $MissionClass -Toolbox $toolbox -RetryCount $retryCount -Tier $tier)

        $green = (
            $eval.JsonValid -and
            $eval.Schema -ge 1.0 -and
            $eval.Lock -ge 1.0 -and
            $eval.Scope -ge 1.0 -and
            (
                $MissionClass -ne 'TRANSACTION_SAFETY' -or
                (
                    $eval.Authority -ge 1.0 -and
                    ($toolbox -contains 'CANDIDATE_VTC')
                )
            ) -and
            (
                $MissionClass -ne 'MEMORY_RECALL' -or
                ($toolbox -contains 'VCC_VSP')
            ) -and
            (
                $MissionClass -ne 'MODEL_ESCALATION_TEST' -or
                (
                    ($toolbox -contains 'LOCK_SCOPE') -and
                    ($toolbox -contains 'VCC_VSP') -and
                    ($toolbox -contains 'CANDIDATE_VTC') -and
                    $eval.Authority -ge 1.0 -and
                    $eval.Confidence -ge 0.90
                )
            )
        )

        Write-Host "      Observe  : latency=$($call.LatencyMs)ms tok/s=$($call.TokensPerSec) prompt=$($call.PromptTokens) completion=$($call.CompletionTokens)"
        Write-Host "      Evaluate : json=$($eval.JsonValid) schema=$($eval.Schema) lock=$($eval.Lock) scope=$($eval.Scope) authority=$($eval.Authority) confidence=$($eval.Confidence)"
        Write-Host "      Diagnose : $($diagnosis -join ', ')"

        $decision = $null

        if (-not $green) {
            $retryCount++

            $decision = Apply-Diagnosis `
                -Diagnosis $diagnosis `
                -Toolbox $toolbox `
                -Channels $channels `
                -MasterThrottle $master `
                -Tier $tier

            $oldTier = $tier
            $oldToolbox = @($toolbox)
            $oldMaster = $master

            $toolbox = @($decision.Toolbox)
            $channels = $decision.Channels
            $master = $decision.MasterThrottle
            $tier = $decision.Tier

            if ($tier -ne $oldTier -and [string]::IsNullOrWhiteSpace($modelByTier[$tier])) {
                Write-Host "      Escalation target $tier unavailable; retaining $oldTier." -ForegroundColor Yellow
                $tier = $oldTier
            }

            Write-Host "      Decision : throttle $oldMaster% -> $master%"
            Write-Host "                 tier $oldTier -> $tier"
            Write-Host "                 toolbox [$($oldToolbox -join ', ')] -> [$($toolbox -join ', ')]"

            foreach ($reason in @($decision.Reasons)) {
                Write-Host "                 - $reason"
            }
        }
        else {
            Write-Host '      Decision : GREEN — required mission safety equipment present; hold runtime and stop.' -ForegroundColor Green
        }

        $cycleRecord = [ordered]@{
            cycle=$cycle
            model_used=$model
            tier_after_decision=$tier
            throttle_after_decision=$master
            toolbox_after_decision=@($toolbox)
            observation=[ordered]@{
                latency_ms=$call.LatencyMs
                prompt_tokens=$call.PromptTokens
                completion_tokens=$call.CompletionTokens
                tokens_per_sec=$call.TokensPerSec
                finish_reason=$call.FinishReason
            }
            evaluation=[ordered]@{
                json_valid=$eval.JsonValid
                schema=$eval.Schema
                lock=$eval.Lock
                scope=$eval.Scope
                authority=$eval.Authority
                unknowns=$eval.Unknowns
                confidence=$eval.Confidence
                missing=@($eval.Missing)
            }
            diagnosis=@($diagnosis)
            green=$green
            decision=if ($null -ne $decision) {
                [ordered]@{
                    next_tier=$tier
                    next_throttle=$master
                    next_toolbox=@($toolbox)
                    reasons=@($decision.Reasons)
                }
            } else {
                $null
            }
        }

        $cycles.Add([pscustomobject]$cycleRecord)
        Write-Json (Join-Path $cycleRoot 'cycle_receipt.json') $cycleRecord

        if ($green) {
            break
        }
    }
    catch {
        $err = $_.Exception.Message
        $errorClass = Classify-ExecutionError -Message $err

        Set-Content -LiteralPath (Join-Path $cycleRoot 'error.txt') -Value $err -Encoding UTF8
        Write-Host "      ERROR    : $err" -ForegroundColor Red
        Write-Host "      CLASS    : $errorClass" -ForegroundColor Yellow

        if ($errorClass -eq 'INFRASTRUCTURE_ERROR') {
            Write-Host '      ACTION   : STOP — do not blame/escalate model for harness failure.' -ForegroundColor Yellow

            $cycles.Add([pscustomobject][ordered]@{
                cycle=$cycle
                model=$model
                tier=$tier
                throttle=$master
                toolbox=@($toolbox)
                green=$false
                error_class=$errorClass
                error=$err
            })

            break
        }

        $retryCount++

        if ($errorClass -eq 'MODEL_OR_UNKNOWN_ERROR') {
            $order = @('3B4B','8B','12B','30B')
            $tierIndex = [array]::IndexOf($order, $tier)

            if ($tierIndex -ge 0 -and $tierIndex -lt ($order.Count - 1)) {
                $candidateTier = $order[$tierIndex + 1]

                if (-not [string]::IsNullOrWhiteSpace($modelByTier[$candidateTier])) {
                    Write-Host "      FAILOVER : $tier -> $candidateTier" -ForegroundColor Yellow
                    $tier = $candidateTier
                }
            }
        }
        else {
            Write-Host '      ACTION   : retry same tier; provider/runtime issue is not model starvation.' -ForegroundColor Yellow
        }
    }
}

Write-Host ''
Write-Host '[4/5] FINAL STATE'

$status = if ($green) { 'GREEN' } else { 'EXHAUSTED_WITHOUT_GREEN' }

Write-Host "  Status   : $status"
Write-Host "  Cycles   : $($cycles.Count)"
Write-Host "  Tier     : $tier"
Write-Host "  Model    : $($modelByTier[$tier])"
Write-Host "  Throttle : $master%"
Write-Host "  Toolbox  : $($toolbox -join ', ')"

$receipt = [ordered]@{
    schema='vertex.booster.live-throttle-experiment.v1.4'
    run_id=$runId
    completed_at=(Get-Date).ToString('o')
    mission_class=$MissionClass
    status=$status
    green=$green
    cycles=@($cycles.ToArray())
    final=[ordered]@{
        tier=$tier
        model=$modelByTier[$tier]
        master_throttle=$master
        channels=$channels
        toolbox=@($toolbox)
    }
    safety=[ordered]@{
        canonical_mutation='NONE'
        vtc_execution='NONE'
    }
}

$receiptPath = Join-Path $runRoot 'VERTEX_BOOSTER_LIVE_THROTTLE_RECEIPT.json'
Write-Json $receiptPath $receipt

Write-Host ''
Write-Host '[5/5] RECEIPT'
Write-Host "  $receiptPath"

Banner 'VERTEX BOOSTER LIVE THROTTLE COMPLETE'

Write-Host "Status             : $status"
Write-Host "Cycles             : $($cycles.Count)"
Write-Host "Final Tier         : $tier"
Write-Host "Final Model        : $($modelByTier[$tier])"
Write-Host "Final Throttle     : $master%"
Write-Host "Final Toolbox      : $($toolbox -join ', ')"
Write-Host ''
Write-Host 'CANONICAL MUTATION : NONE'
Write-Host 'VTC EXECUTION      : NONE'
Write-Host ''

if ($green) {
    Write-Host 'BOOSTER FOUND A GREEN RUNTIME BOUNDARY.' -ForegroundColor Green
}
else {
    Write-Host 'BOOSTER DID NOT REACH GREEN WITHIN THE CYCLE BUDGET.' -ForegroundColor Yellow
}

Write-Host '轟。' -ForegroundColor Green
