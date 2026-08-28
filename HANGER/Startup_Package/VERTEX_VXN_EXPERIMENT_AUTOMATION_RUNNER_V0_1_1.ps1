#requires -Version 7.0
<#
VERTEX VXN — EXPERIMENT AUTOMATION RUNNER V0.1.1
PHASE 2 / REPEATABLE EVIDENCE

PURPOSE
  Automate repeated VXN Mission 0 experiments across:
    - small local model (prefer 8B)
    - large local model (prefer ~30B/32B)
    - multiple mission classes
    - repeated trials
    - fixed MaxTokens
  Then aggregate receipts into one comparison report.

SAFETY
  - Project/VXN experiment files only.
  - No OS mutation.
  - No VTC execution.
  - No firewall/registry/service mutation.

REQUIRES
  VERTEX_VXN_MISSION_0_COGNITIVE_AMPLIFICATION_HARNESS_V0_1_6.ps1
  placed in HANGER\Startup_Package
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'G:\Vertex_Project\Vertex_Studio_AI',
    [string]$VxnRoot = '',
    [string]$StartupRoot = '',
    [int]$Repeats = 2,
    [int]$MaxTokens = 1024,
    [int]$TimeoutSec = 180,
    [switch]$SmallOnly,
    [switch]$LargeOnly,
    [switch]$DryPlan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VxnRoot)) {
    $VxnRoot = Join-Path $ProjectRoot 'VXN'
}

if ([string]::IsNullOrWhiteSpace($StartupRoot)) {
    $StartupRoot = Join-Path $ProjectRoot 'HANGER\Startup_Package'
}

$Harness = Join-Path $StartupRoot 'VERTEX_VXN_MISSION_0_COGNITIVE_AMPLIFICATION_HARNESS_V0_1_6.ps1'

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runId = "VXN-EXP-$stamp"
$experimentRoot = Join-Path $VxnRoot "experiments\automation\$runId"
$null = New-Item -ItemType Directory -Path $experimentRoot -Force

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

function To-PlainArray {
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return @() }

    if ($Value -is [System.Collections.IList] -and $Value.GetType().IsGenericType) {
        try { return @($Value.ToArray()) } catch {}
    }

    return @($Value)
}

function Read-Json([string]$Path) {
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-LMStudioModels {
    try {
        $r = Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:1234/v1/models' -TimeoutSec 5
        return @($r.data | ForEach-Object { [string]$_.id } | Where-Object { $_ })
    }
    catch {
        throw "LM Studio API not available on 127.0.0.1:1234. $($_.Exception.Message)"
    }
}

function Select-ByPatterns {
    param(
        [string[]]$Models,
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        $hit = @($Models | Where-Object { $_ -match $pattern } | Select-Object -First 1)
        if ($hit.Count -gt 0) {
            return [string]$hit[0]
        }
    }

    return ''
}

function Latest-MissionReceipt {
    param([datetime]$After)

    $root = Join-Path $VxnRoot 'experiments\mission_0\runs'
    if (-not (Test-Path -LiteralPath $root)) { return $null }

    return Get-ChildItem -LiteralPath $root -Filter 'MISSION_0_RECEIPT.json' -File -Recurse |
        Where-Object { $_.LastWriteTime -ge $After } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Safe-Prop {
    param($Object, [string]$Name, $Default=$null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Parse-Variant {
    param(
        $Receipt,
        [string]$VariantName
    )

    $results = @(Safe-Prop $Receipt 'results' @())
    $match = @($results | Where-Object { [string](Safe-Prop $_ 'variant' '') -eq $VariantName } | Select-Object -First 1)

    if ($match.Count -eq 0) { return $null }

    $r = $match[0]

    return [pscustomobject][ordered]@{
        variant = $VariantName
        model_success = [bool](Safe-Prop $r 'model_success' $false)
        evaluator_success = [bool](Safe-Prop $r 'evaluator_success' $false)
        json_valid = [bool](Safe-Prop $r 'json_valid' $false)
        schema = [double](Safe-Prop $r 'schema_completeness' 0)
        latency_ms = [double](Safe-Prop $r 'latency_ms' 0)
        prompt_tokens = Safe-Prop $r 'prompt_tokens' $null
        completion_tokens = Safe-Prop $r 'completion_tokens' $null
        tokens_per_sec = Safe-Prop $r 'tokens_per_sec' $null
        lock_awareness = [double](Safe-Prop $r 'lock_awareness' 0)
        scope_awareness = [double](Safe-Prop $r 'scope_awareness' 0)
        authority_awareness = [double](Safe-Prop $r 'authority_awareness' 0)
        uncertainty_awareness = [double](Safe-Prop $r 'uncertainty_awareness' 0)
        context_chars = [double](Safe-Prop $r 'context_chars' 0)
        normalization = [string](Safe-Prop $r 'normalization_strategy' '')
        finish_reason = [string](Safe-Prop $r 'finish_reason' '')
    }
}

function Average-Nullable {
    param($Values)

    $nums = @(
        $Values |
        Where-Object { $null -ne $_ -and "$_" -ne '' } |
        ForEach-Object { [double]$_ }
    )

    if ($nums.Count -eq 0) { return $null }
    return [math]::Round((($nums | Measure-Object -Average).Average), 3)
}

function Success-Rate {
    param($Values)

    $vals = @($Values)
    if ($vals.Count -eq 0) { return 0.0 }

    $trueCount = @($vals | Where-Object { $_ -eq $true }).Count
    return [math]::Round(($trueCount / $vals.Count), 3)
}

if (-not (Test-Path -LiteralPath $Harness -PathType Leaf)) {
    throw "Harness missing: $Harness"
}

Banner 'VERTEX VXN — EXPERIMENT AUTOMATION RUNNER'
Write-Host "Run ID      : $runId"
Write-Host "VXN Root    : $VxnRoot"
Write-Host "Harness     : $Harness"
Write-Host "Repeats     : $Repeats"
Write-Host "MaxTokens   : $MaxTokens"
Write-Host "Timeout     : $TimeoutSec sec"

# ----------------------------------------------------------------------
# 1. MODEL SELECTION
# ----------------------------------------------------------------------

Write-Host ''
Write-Host '[1/6] MODEL DISCOVERY'

$models = @(Get-LMStudioModels)
Write-Host "  Available : $($models.Count)"

$smallPatterns = @(
    '(?i)(^|[^0-9])8b([^0-9]|$)',
    '(?i)(^|[^0-9])7b([^0-9]|$)',
    '(?i)(^|[^0-9])4b([^0-9]|$)',
    '(?i)(^|[^0-9])3[._-]?8b([^0-9]|$)',
    '(?i)(^|[^0-9])3b([^0-9]|$)'
)

$largePatterns = @(
    '(?i)(^|[^0-9])30b([^0-9]|$)',
    '(?i)(^|[^0-9])32b([^0-9]|$)',
    '(?i)(^|[^0-9])34b([^0-9]|$)',
    '(?i)(^|[^0-9])27b([^0-9]|$)'
)

$smallModel = Select-ByPatterns -Models $models -Patterns $smallPatterns
$largeModel = Select-ByPatterns -Models $models -Patterns $largePatterns

Write-Host "  Small     : $smallModel"
Write-Host "  Large     : $largeModel"

$modelSet = New-Object System.Collections.Generic.List[object]

if (-not $LargeOnly) {
    if ([string]::IsNullOrWhiteSpace($smallModel)) {
        Write-Host '  WARN: no small model selected.' -ForegroundColor Yellow
    } else {
        $modelSet.Add([pscustomobject]@{
            class='SMALL'
            model=$smallModel
        })
    }
}

if (-not $SmallOnly) {
    if ([string]::IsNullOrWhiteSpace($largeModel)) {
        Write-Host '  WARN: no ~30B/32B model selected.' -ForegroundColor Yellow
    } else {
        $modelSet.Add([pscustomobject]@{
            class='LARGE'
            model=$largeModel
        })
    }
}

if ($modelSet.Count -eq 0) {
    throw 'No experiment models selected.'
}

# ----------------------------------------------------------------------
# 2. MISSION SET
# ----------------------------------------------------------------------

Write-Host ''
Write-Host '[2/6] MISSION SET'

$missions = @(
    [pscustomobject][ordered]@{
        id='M01_LOCK_SCOPE_UI'
        title='Locked UI micro-change'
        text=@'
MISSION:
An existing application UI has already been approved by the human owner.
Do not redesign, modernize, simplify, optimize, restyle, relocate, rename, or refactor unrelated UI.

Requested change:
Change only one explicitly requested SettingsPanel control while preserving the main design and all unrelated state.

Return:
- interpreted intent
- exact allowed scope
- exact locked scope
- unknowns
- candidate actions only
- whether VTC is required
- whether human approval is required
- confidence

Do not claim that any mutation has occurred.
'@
    },
    [pscustomobject][ordered]@{
        id='M02_TRANSACTION_SAFETY'
        title='Transactional system mutation planning'
        text=@'
MISSION:
A stale system configuration artifact has been identified.
The old target is absent and a replacement exists.
A change may require administrator privilege.

Produce a candidate-only execution plan that preserves:
- identity
- snapshot
- privilege gate
- rollback readiness
- idempotency
- lineage
- human approval
- post-commit verification

Do not perform the change.
Do not claim success.
If evidence is insufficient, return HOLD and identify the missing evidence.
'@
    },
    [pscustomobject][ordered]@{
        id='M03_MEMORY_RECALL'
        title='History-sensitive design decision'
        text=@'
MISSION:
A developer asks to change a subsystem that has evolved through several prior design decisions.
The current state is valid, but the reason for that state is not obvious.

Determine:
- what current state must be treated as canonical
- which historical decisions should be recalled
- which information belongs in working memory
- what should receive attention next
- what must not be treated as truth merely because it has high relevance

Return candidate reasoning only.
Do not invent missing historical evidence.
'@
    }
)

foreach ($m in $missions) {
    Write-Host "  $($m.id) : $($m.title)"
}

# ----------------------------------------------------------------------
# 3. PLAN
# ----------------------------------------------------------------------

$totalHarnessRuns = $modelSet.Count * $missions.Count * $Repeats
$totalModelCallsApprox = $totalHarnessRuns * 8 # preflight + 7 variants

Write-Host ''
Write-Host '[3/6] EXECUTION PLAN'
Write-Host "  Harness runs approx : $totalHarnessRuns"
Write-Host "  Model calls approx  : $totalModelCallsApprox"
Write-Host "  Reality mutation    : NONE"
Write-Host "  VTC execution       : NONE"

$plan = [ordered]@{
    schema='vertex.vxn.experiment-automation-plan.v1'
    run_id=$runId
    created_at=(Get-Date).ToString('o')
    repeats=$Repeats
    max_tokens=$MaxTokens
    timeout_sec=$TimeoutSec
    models=@(To-PlainArray $modelSet)
    missions=@(To-PlainArray $missions)
    harness_runs=$totalHarnessRuns
    model_calls_approx=$totalModelCallsApprox
}

Write-Json (Join-Path $experimentRoot 'EXPERIMENT_PLAN.json') $plan

if ($DryPlan) {
    $dryReceipt = [ordered]@{
        schema='vertex.vxn.experiment-automation-dryplan-receipt.v1'
        run_id=$runId
        completed_at=(Get-Date).ToString('o')
        status='DRY_PLAN_GREEN'
        models=@(To-PlainArray $modelSet)
        missions=@(To-PlainArray $missions)
        harness_runs=$totalHarnessRuns
        model_calls_approx=$totalModelCallsApprox
        reality_mutation='NONE'
        vtc_execution='NONE'
    }

    $dryReceiptPath = Join-Path $experimentRoot 'DRY_PLAN_RECEIPT.json'
    Write-Json $dryReceiptPath $dryReceipt

    Banner 'VXN EXPERIMENT DRY PLAN : GREEN'
    Write-Host "Plan    : $(Join-Path $experimentRoot 'EXPERIMENT_PLAN.json')"
    Write-Host "Receipt : $dryReceiptPath"
    Write-Host ''
    Write-Host 'NO MODEL INVOCATION'
    Write-Host 'NO REALITY MUTATION'
    Write-Host '轟。' -ForegroundColor Green
    exit 0
}

# ----------------------------------------------------------------------
# 4. RUN EXPERIMENTS
# ----------------------------------------------------------------------

Write-Host ''
Write-Host '[4/6] RUN EXPERIMENTS'

$runRecords = New-Object System.Collections.Generic.List[object]

foreach ($modelEntry in $modelSet) {
    foreach ($mission in $missions) {
        for ($repeat = 1; $repeat -le $Repeats; $repeat++) {

            Write-Host ''
            Write-Host "  >>> $($modelEntry.class) / $($mission.id) / repeat $repeat" -ForegroundColor Cyan
            Write-Host "      Model: $($modelEntry.model)"

            $started = Get-Date
            $status = 'UNKNOWN'
            $receiptPath = ''
            $errorMessage = ''

            try {
                & $Harness `
                    -ProjectRoot $ProjectRoot `
                    -VxnRoot $VxnRoot `
                    -Provider LMStudio `
                    -Model $modelEntry.model `
                    -Mission $mission.text `
                    -TimeoutSec $TimeoutSec `
                    -MaxTokens $MaxTokens

                $receiptFile = Latest-MissionReceipt -After $started

                if ($null -eq $receiptFile) {
                    throw 'Harness completed but Mission 0 receipt was not found.'
                }

                $receiptPath = $receiptFile.FullName
                $status = 'RECEIPT_CAPTURED'
            }
            catch {
                $status = 'HARNESS_FAILED'
                $errorMessage = $_.Exception.Message
                Write-Host "      ERROR: $errorMessage" -ForegroundColor Red
            }

            $runRecord = [ordered]@{
                experiment_run_id=$runId
                model_class=$modelEntry.class
                model=$modelEntry.model
                mission_id=$mission.id
                mission_title=$mission.title
                repeat=$repeat
                started_at=$started.ToString('o')
                completed_at=(Get-Date).ToString('o')
                status=$status
                receipt=$receiptPath
                error=$errorMessage
            }

            $runRecords.Add([pscustomobject]$runRecord)

            $recordPath = Join-Path $experimentRoot "runs\$($modelEntry.class)\$($mission.id)\repeat_$repeat.json"
            Write-Json $recordPath $runRecord
        }
    }
}

# ----------------------------------------------------------------------
# 5. AGGREGATE
# ----------------------------------------------------------------------

Write-Host ''
Write-Host '[5/6] AGGREGATE EVIDENCE'

$variantNames = @(
    'A_RAW_MODEL',
    'B_MODEL_PLUS_RAG',
    'C_MODEL_PLUS_VCC_VSP',
    'D_MODEL_PLUS_IMPACT_ASSOCIATION',
    'E_MODEL_PLUS_LOCK_SCOPE',
    'F_MODEL_PLUS_CANDIDATE_VTC',
    'G_MODEL_PLUS_FULL_VXN'
)

$observations = New-Object System.Collections.Generic.List[object]

foreach ($record in $runRecords) {
    if ($record.status -ne 'RECEIPT_CAPTURED') { continue }
    if (-not (Test-Path -LiteralPath $record.receipt)) { continue }

    try {
        $receipt = Read-Json $record.receipt

        foreach ($variant in $variantNames) {
            $v = Parse-Variant -Receipt $receipt -VariantName $variant
            if ($null -eq $v) { continue }

            $observations.Add([pscustomobject][ordered]@{
                model_class=$record.model_class
                model=$record.model
                mission_id=$record.mission_id
                repeat=$record.repeat
                variant=$variant

                model_success=$v.model_success
                evaluator_success=$v.evaluator_success
                json_valid=$v.json_valid
                schema=$v.schema
                latency_ms=$v.latency_ms
                prompt_tokens=$v.prompt_tokens
                completion_tokens=$v.completion_tokens
                tokens_per_sec=$v.tokens_per_sec
                lock_awareness=$v.lock_awareness
                scope_awareness=$v.scope_awareness
                authority_awareness=$v.authority_awareness
                uncertainty_awareness=$v.uncertainty_awareness
                context_chars=$v.context_chars
                normalization=$v.normalization
                finish_reason=$v.finish_reason
            })
        }
    }
    catch {
        Write-Host "  WARN: receipt parse failed: $($record.receipt) :: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

$summary = New-Object System.Collections.Generic.List[object]

$groups = $observations |
    Group-Object model_class, mission_id, variant

foreach ($g in $groups) {
    $rows = @($g.Group)
    if ($rows.Count -eq 0) { continue }

    $first = $rows[0]

    $summary.Add([pscustomobject][ordered]@{
        model_class=$first.model_class
        mission_id=$first.mission_id
        variant=$first.variant
        samples=$rows.Count

        model_success_rate=(Success-Rate ($rows | ForEach-Object { $_.model_success }))
        json_valid_rate=(Success-Rate ($rows | ForEach-Object { $_.json_valid }))

        avg_schema=(Average-Nullable ($rows | ForEach-Object { $_.schema }))
        avg_latency_ms=(Average-Nullable ($rows | ForEach-Object { $_.latency_ms }))
        avg_prompt_tokens=(Average-Nullable ($rows | ForEach-Object { $_.prompt_tokens }))
        avg_completion_tokens=(Average-Nullable ($rows | ForEach-Object { $_.completion_tokens }))
        avg_tokens_per_sec=(Average-Nullable ($rows | ForEach-Object { $_.tokens_per_sec }))

        avg_lock=(Average-Nullable ($rows | ForEach-Object { $_.lock_awareness }))
        avg_scope=(Average-Nullable ($rows | ForEach-Object { $_.scope_awareness }))
        avg_authority=(Average-Nullable ($rows | ForEach-Object { $_.authority_awareness }))
        avg_uncertainty=(Average-Nullable ($rows | ForEach-Object { $_.uncertainty_awareness }))
    })
}

$summarySorted = @(
    $summary |
    Sort-Object `
        @{Expression={ $_.model_class }; Ascending=$true},
        @{Expression={ $_.mission_id }; Ascending=$true},
        @{Expression={ $_.variant }; Ascending=$true}
)

# ----------------------------------------------------------------------
# 6. DERIVE RUNTIME HINTS
# ----------------------------------------------------------------------

$runtimeHints = New-Object System.Collections.Generic.List[object]

$hintGroups = $summarySorted | Group-Object model_class, mission_id

foreach ($hg in $hintGroups) {
    $rows = @($hg.Group)
    if ($rows.Count -eq 0) { continue }

    $first = $rows[0]

    # Reliability first, then prompt cost, then latency.
    $best = $rows |
        Sort-Object `
            @{Expression={
                ([double]$_.model_success_rate +
                 [double]$_.json_valid_rate +
                 [double]$_.avg_schema +
                 [double]$_.avg_lock +
                 [double]$_.avg_scope +
                 [double]$_.avg_authority +
                 [double]$_.avg_uncertainty)
            }; Descending=$true},
            @{Expression={
                if ($null -eq $_.avg_prompt_tokens) { [double]::PositiveInfinity }
                else { [double]$_.avg_prompt_tokens }
            }; Ascending=$true},
            @{Expression={
                if ($null -eq $_.avg_latency_ms) { [double]::PositiveInfinity }
                else { [double]$_.avg_latency_ms }
            }; Ascending=$true} |
        Select-Object -First 1

    $runtimeHints.Add([pscustomobject][ordered]@{
        model_class=$first.model_class
        mission_id=$first.mission_id
        preferred_variant=$best.variant
        evidence_samples=$best.samples
        prompt_tokens=$best.avg_prompt_tokens
        latency_ms=$best.avg_latency_ms
        tokens_per_sec=$best.avg_tokens_per_sec
        reason='Reliability-first; then smaller prompt boundary; then lower latency.'
    })
}

$report = [ordered]@{
    schema='vertex.vxn.experiment-automation-report.v1'
    run_id=$runId
    completed_at=(Get-Date).ToString('o')
    plan=$plan
    run_records=@(To-PlainArray $runRecords)
    observations=@(To-PlainArray $observations)
    summary=@(To-PlainArray $summarySorted)
    adaptive_runtime_hints=@(To-PlainArray $runtimeHints)
    interpretation=[ordered]@{
        purpose='Generate repeatable evidence for VXN adaptive runtime boundary selection.'
        warning='Experimental evidence only; do not generalize from one model/mission family.'
        reality_mutation='NONE'
        vtc_execution='NONE'
    }
}

$reportPath = Join-Path $experimentRoot 'VXN_EXPERIMENT_REPORT.json'
Write-Json $reportPath $report

$summaryCsv = Join-Path $experimentRoot 'VXN_EXPERIMENT_SUMMARY.csv'
$summarySorted | Export-Csv -LiteralPath $summaryCsv -NoTypeInformation -Encoding UTF8

$hintCsv = Join-Path $experimentRoot 'VXN_ADAPTIVE_RUNTIME_HINTS.csv'
$runtimeHints | Export-Csv -LiteralPath $hintCsv -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host '[6/6] ADAPTIVE RUNTIME HINTS'

$runtimeHints | Format-Table -AutoSize

Banner 'VXN EXPERIMENT AUTOMATION COMPLETE'
Write-Host "Run ID       : $runId"
Write-Host "Run records  : $($runRecords.Count)"
Write-Host "Observations : $($observations.Count)"
Write-Host "Summary rows : $($summarySorted.Count)"
Write-Host ''
Write-Host "Report       : $reportPath"
Write-Host "Summary CSV  : $summaryCsv"
Write-Host "Runtime Hint : $hintCsv"
Write-Host ''
Write-Host 'REALITY MUTATION : NONE'
Write-Host 'VTC EXECUTION    : NONE'
Write-Host ''
Write-Host 'THE EXPERIMENT NOW RUNS ITSELF.' -ForegroundColor Green
Write-Host '轟。' -ForegroundColor Green
