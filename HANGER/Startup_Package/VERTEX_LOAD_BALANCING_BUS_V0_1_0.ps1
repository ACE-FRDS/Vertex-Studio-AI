#requires -Version 7.0
<#
VERTEX — LOAD BALANCING BUS V0.1.0

PURPOSE
  Convert Scheduler Bus Handoff into an evidence-driven routing plan.

INPUT
  - CURRENT_BUS_HANDOFF.json
  - CURRENT_SCHEDULER_STATE.json
  - Available local model runtimes from LM Studio

OUTPUT
  - Route plan
  - Lane allocation
  - Runtime target assignment
  - Capacity/backoff policy
  - Reroute/fallback policy
  - Bus current state

IMPORTANT
  This Bus DOES NOT invoke models or agents.
  It only plans traffic routing.

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

$schedulerRoot = Join-Path $VxnRoot 'runtime\scheduler'
$handoffPath = Join-Path $schedulerRoot 'bus_handoff\CURRENT_BUS_HANDOFF.json'
$schedulerStatePath = Join-Path $schedulerRoot 'state\CURRENT_SCHEDULER_STATE.json'

$busRoot = Join-Path $VxnRoot 'runtime\load_balancing_bus'
$routeRoot = Join-Path $busRoot 'routes'
$stateRoot = Join-Path $busRoot 'state'
$receiptRoot = Join-Path $busRoot 'receipts'
$policyRoot = Join-Path $busRoot 'policies'

@($busRoot,$routeRoot,$stateRoot,$receiptRoot,$policyRoot) | ForEach-Object {
    $null = New-Item -ItemType Directory -Force -Path $_
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$busId = "VXN-BUS-$stamp"

function Banner([string]$Text) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Magenta
    Write-Host " $Text" -ForegroundColor Magenta
    Write-Host '============================================================' -ForegroundColor Magenta
}

function Write-Json([string]$Path,$Object) {
    $parent = Split-Path -Parent $Path
    if ($parent) {
        $null = New-Item -ItemType Directory -Force -Path $parent
    }

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

    $p = $Object.PSObject.Properties[$Name]

    if ($null -eq $p -or $null -eq $p.Value) {
        return $Default
    }

    return $p.Value
}

function Get-LMStudioModels {
    try {
        $r = Invoke-RestMethod `
            -Method Get `
            -Uri 'http://127.0.0.1:1234/v1/models' `
            -TimeoutSec 5

        return @(
            $r.data |
            ForEach-Object { [string]$_.id } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }
    catch {
        return @()
    }
}

function Get-ModelFamily([string]$Model) {
    if ([string]::IsNullOrWhiteSpace($Model)) { return 'UNKNOWN' }

    $id = $Model.ToLowerInvariant()

    if ($id -match 'hunyuan') { return 'HUNYUAN' }
    if ($id -match 'deepseek') { return 'DEEPSEEK' }
    if ($id -match 'qwen') { return 'QWEN' }
    if ($id -match 'gemma') { return 'GEMMA' }
    if ($id -match 'llama') { return 'LLAMA' }

    return 'OTHER'
}

function Get-ModelSize([string]$Model) {
    if ([string]::IsNullOrWhiteSpace($Model)) { return 0.0 }

    $clean = $Model.ToLowerInvariant() -replace '(?i)a\d+(?:\.\d+)?b',''
    $matches = [regex]::Matches(
        $clean,
        '(?<![a-z0-9])(\d+(?:\.\d+)?)b(?![a-z0-9])'
    )

    $sizes = @()

    foreach ($m in $matches) {
        $v = 0.0
        if ([double]::TryParse($m.Groups[1].Value,[ref]$v)) {
            $sizes += $v
        }
    }

    if ($sizes.Count -eq 0) { return 0.0 }

    return [double](($sizes | Measure-Object -Maximum).Maximum)
}

function Get-RuntimeTarget {
    param(
        [string]$RequestedModel,
        [string[]]$AvailableModels
    )

    if ($AvailableModels -contains $RequestedModel) {
        return [pscustomobject]@{
            Runtime='LM_STUDIO'
            Model=$RequestedModel
            Match='EXACT'
        }
    }

    $family = Get-ModelFamily $RequestedModel
    $size = Get-ModelSize $RequestedModel

    $familyCandidates = @(
        $AvailableModels |
        Where-Object {
            (Get-ModelFamily $_) -eq $family
        }
    )

    if ($familyCandidates.Count -gt 0) {
        $ranked = @(
            $familyCandidates |
            ForEach-Object {
                $candidateSize = Get-ModelSize $_

                [pscustomobject]@{
                    Model=$_
                    Distance=[math]::Abs($candidateSize - $size)
                }
            } |
            Sort-Object Distance
        )

        return [pscustomobject]@{
            Runtime='LM_STUDIO'
            Model=$ranked[0].Model
            Match='FAMILY_NEAREST_SIZE'
        }
    }

    return [pscustomobject]@{
        Runtime='UNRESOLVED'
        Model=$RequestedModel
        Match='NO_TARGET'
    }
}

function Build-Lanes {
    param(
        [array]$Tasks,
        [int]$RequestedWidth,
        [string[]]$AvailableModels
    )

    $lanes = @()
    $laneCount = [math]::Max(1,$RequestedWidth)

    for ($i=0; $i -lt $laneCount; $i++) {
        $lanes += [ordered]@{
            lane_id="LANE-$($i+1)"
            state='IDLE'
            task=$null
            runtime=$null
            model=$null
            match=$null
        }
    }

    for ($i=0; $i -lt $Tasks.Count; $i++) {
        $laneIndex = $i % $laneCount
        $task = $Tasks[$i]

        $requestedModel = [string](Get-Prop $task 'model' '')
        $target = Get-RuntimeTarget `
            -RequestedModel $requestedModel `
            -AvailableModels $AvailableModels

        $lanes[$laneIndex] = [ordered]@{
            lane_id="LANE-$($laneIndex+1)"
            state='ASSIGNED'
            task=$task
            runtime=$target.Runtime
            model=$target.Model
            match=$target.Match
        }
    }

    return $lanes
}

Banner 'VERTEX — LOAD BALANCING BUS V0.1.0'

$handoff = Read-JsonSafe $handoffPath
$schedulerState = Read-JsonSafe $schedulerStatePath

if ($null -eq $handoff) {
    throw "Scheduler Bus Handoff not found: $handoffPath"
}

$availableModels = @(Get-LMStudioModels)

$scheduleId = [string](Get-Prop $handoff 'schedule_id' 'UNKNOWN')
$missionClass = [string](Get-Prop $handoff 'mission_class' 'GENERAL')
$routes = @(Get-Prop $handoff 'routes' @())
$capacity = Get-Prop $handoff 'capacity_contract' $null

$initialWidth = [int](Get-Prop $capacity 'initial_width' 1)
$minimumWidth = [int](Get-Prop $capacity 'minimum_width' 1)

Write-Host "Bus ID         : $busId"
Write-Host "Schedule ID    : $scheduleId"
Write-Host "Mission Class  : $missionClass"
Write-Host "Routes         : $($routes.Count)"
Write-Host "Initial Width  : $initialWidth"
Write-Host "Available LMs  : $($availableModels.Count)"

$routePlans = @()
$allResolved = $true

Write-Host ''
Write-Host '[ROUTE PLANNING]' -ForegroundColor Cyan

foreach ($route in $routes) {
    $routeId = [string](Get-Prop $route 'route_id' '')
    $wave = [int](Get-Prop $route 'wave' 0)
    $requestedWidth = [int](Get-Prop $route 'requested_width' 1)
    $tasks = @(Get-Prop $route 'tasks' @())

    $lanes = @(Build-Lanes `
        -Tasks $tasks `
        -RequestedWidth $requestedWidth `
        -AvailableModels $availableModels)

    $unresolved = @(
        $lanes |
        Where-Object {
            [string](Get-Prop $_ 'runtime' '') -eq 'UNRESOLVED'
        }
    )

    if ($unresolved.Count -gt 0) {
        $allResolved = $false
    }

    $routePlan = [ordered]@{
        route_id=$routeId
        wave=$wave
        requested_width=$requestedWidth
        lane_count=$lanes.Count
        lanes=$lanes

        backoff_policy=[ordered]@{
            on_http_500='WIDTH_MINUS_1'
            minimum_width=$minimumWidth
            retry_failed_tasks_only=$true
            preserve_successful_lane_results=$true
        }

        reroute_policy=[ordered]@{
            on_runtime_unavailable='FAMILY_NEAREST_SIZE'
            on_family_unavailable='HOLD_ROUTE'
            allow_provider_fallback=$false
        }

        state=if ($unresolved.Count -eq 0) {
            'ROUTED'
        } else {
            'PARTIAL_ROUTE'
        }
    }

    $routePlans += $routePlan

    Write-Host "  $routeId / WAVE $wave"
    Write-Host "      width=$requestedWidth lanes=$($lanes.Count) state=$($routePlan.state)"

    foreach ($lane in $lanes) {
        $task = Get-Prop $lane 'task' $null

        if ($null -eq $task) {
            Write-Host "      $($lane.lane_id) IDLE"
        }
        else {
            Write-Host (
                "      {0} role={1,-14} runtime={2,-12} model={3} match={4}" -f `
                $lane.lane_id,
                (Get-Prop $task 'role' ''),
                $lane.runtime,
                $lane.model,
                $lane.match
            )
        }
    }
}

$commandRoute = Get-Prop $handoff 'command_route' $null
$commandModel = [string](Get-Prop $commandRoute 'model' '')
$commandTarget = Get-RuntimeTarget `
    -RequestedModel $commandModel `
    -AvailableModels $availableModels

if ($commandTarget.Runtime -eq 'UNRESOLVED') {
    $allResolved = $false
}

Write-Host ''
Write-Host '[COMMAND ROUTE]' -ForegroundColor Cyan
Write-Host "  Requested : $commandModel"
Write-Host "  Runtime   : $($commandTarget.Runtime)"
Write-Host "  Model     : $($commandTarget.Model)"
Write-Host "  Match     : $($commandTarget.Match)"

$policy = [ordered]@{
    schema='vertex.load-balancing-bus.policy.v1'
    updated_at=(Get-Date).ToString('o')

    principles=[ordered]@{
        logical_party_decoupled_from_physical_width=$true
        preserve_successful_results_on_backoff=$true
        prefer_exact_model_match=$true
        family_nearest_size_fallback=$true
        provider_fallback_disabled_by_default=$true
    }

    capacity=[ordered]@{
        initial_width=$initialWidth
        minimum_width=$minimumWidth
        on_http_500='DECREMENT_WIDTH_BY_1'
        probe_up_after_stable_wave=$true
    }
}

$policyPath = Join-Path $policyRoot 'CURRENT_BUS_POLICY.json'
Write-Json $policyPath $policy

$plan = [ordered]@{
    schema='vertex.load-balancing-bus.route-plan.v1'
    bus_id=$busId
    schedule_id=$scheduleId
    mission_class=$missionClass
    generated_at=(Get-Date).ToString('o')

    routes=$routePlans

    command_route=[ordered]@{
        requested_model=$commandModel
        runtime=$commandTarget.Runtime
        model=$commandTarget.Model
        match=$commandTarget.Match
        trigger='FIELD_COMPLETE'
    }

    capacity_contract=[ordered]@{
        initial_width=$initialWidth
        minimum_width=$minimumWidth
        reduce_on_http_500=$true
        retry_failed_tasks_only=$true
        probe_up_after_stable_wave=$true
    }

    execution_policy=[ordered]@{
        automatic_execution=$false
        requires_go_signal=$true
        scheduler_controls_order=$true
        bus_controls_route_and_lane=$true
        executor_controls_actual_invocation=$true
    }

    safety=[ordered]@{
        canonical_mutation='NONE'
        vtc_execution='NONE'
        model_invocation='NONE'
        agent_execution='NONE'
    }
}

$planPath = Join-Path $routeRoot "$busId.ROUTE_PLAN.json"
$currentPlanPath = Join-Path $routeRoot 'CURRENT_BUS_ROUTE_PLAN.json'
Write-Json $planPath $plan
Write-Json $currentPlanPath $plan

$state = [ordered]@{
    schema='vertex.load-balancing-bus.current-state.v1'
    updated_at=(Get-Date).ToString('o')
    bus_id=$busId
    schedule_id=$scheduleId
    mission_class=$missionClass
    route_count=$routePlans.Count
    initial_width=$initialWidth
    all_targets_resolved=$allResolved
    state=if ($allResolved) {
        'READY'
    } else {
        'HOLD_UNRESOLVED_TARGETS'
    }
}

$statePath = Join-Path $stateRoot 'CURRENT_BUS_STATE.json'
Write-Json $statePath $state

$receiptPath = Join-Path $receiptRoot "$busId.RECEIPT.json"

Write-Json $receiptPath ([ordered]@{
    schema='vertex.load-balancing-bus.plan-receipt.v1'
    completed_at=(Get-Date).ToString('o')
    bus_id=$busId
    schedule_id=$scheduleId
    route_count=$routePlans.Count
    all_targets_resolved=$allResolved
    state=$state.state
    route_plan=$planPath
    canonical_mutation='NONE'
    vtc_execution='NONE'
    model_invocation='NONE'
    agent_execution='NONE'
})

Write-Host ''
Write-Host '[BUS VALIDATION]' -ForegroundColor Cyan
Write-Host "  All Targets Resolved : $allResolved"
Write-Host "  Bus State            : $($state.state)"
Write-Host "  Route Count          : $($routePlans.Count)"
Write-Host "  Initial Width        : $initialWidth"

Write-Host ''
Write-Host "Route Plan : $planPath"
Write-Host "Current    : $currentPlanPath"
Write-Host "State      : $statePath"
Write-Host "Policy     : $policyPath"
Write-Host "Receipt    : $receiptPath"

Write-Host ''
Write-Host 'AUTO EXECUTION      : DISABLED'
Write-Host 'GO SIGNAL REQUIRED  : YES'
Write-Host 'CANONICAL MUTATION  : NONE'
Write-Host 'VTC EXECUTION       : NONE'
Write-Host 'MODEL INVOCATION    : NONE'
Write-Host 'AGENT EXECUTION     : NONE'
Write-Host ''
Write-Host 'VERTEX LOAD BALANCING BUS READY.'
Write-Host '轟。' -ForegroundColor Green
