#requires -Version 7.0
<#
VERTEX — ADAPTIVE MISSION SCHEDULER V0.1.1

PURPOSE
  Build an execution schedule from existing Vertex World / ARD evidence.

INPUTS
  - CURRENT_FORMATION_PLAN.json
  - CURRENT_ROSTER.json
  - CURRENT_COMMAND_STAFF.json
  - CURRENT_COMMAND_SPECIALTY.json
  - ARD_PARALLEL_WIDTH_MEMORY.json (if available)

OUTPUT
  - Mission queue plan
  - Wave schedule
  - Physical parallel width
  - Model residency hints
  - Runtime capacity hints
  - Command assignment
  - Retry / backoff policy
  - Load Balancing Bus handoff contract

IMPORTANT
  This scheduler DOES NOT execute agents.
  It only creates an evidence-driven execution plan.

SAFETY
  - No model invocation.
  - No agent execution.
  - No canonical mutation.
  - No VTC execution.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'G:\Vertex_Project\Vertex_Studio_AI',
    [string]$VxnRoot = '',
    [int]$MaxWaveSize = 0,
    [bool]$PreferModelResidency = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VxnRoot)) {
    $VxnRoot = Join-Path $ProjectRoot 'VXN'
}

$rpgRoot = Join-Path $VxnRoot 'runtime\rpg'
$formationPath = Join-Path $rpgRoot 'formations\CURRENT_FORMATION_PLAN.json'
$rosterPath = Join-Path $rpgRoot 'roster\CURRENT_ROSTER.json'
$commandStaffPath = Join-Path $rpgRoot 'command_staff\CURRENT_COMMAND_STAFF.json'
$commandSpecialtyPath = Join-Path $rpgRoot 'command_specialty\CURRENT_COMMAND_SPECIALTY.json'
$parallelMemoryPath = Join-Path $VxnRoot 'runtime\booster\parallelism\ARD_PARALLEL_WIDTH_MEMORY.json'

$schedulerRoot = Join-Path $VxnRoot 'runtime\scheduler'
$queueRoot = Join-Path $schedulerRoot 'queues'
$planRoot = Join-Path $schedulerRoot 'plans'
$stateRoot = Join-Path $schedulerRoot 'state'
$receiptRoot = Join-Path $schedulerRoot 'receipts'
$busRoot = Join-Path $schedulerRoot 'bus_handoff'

@($schedulerRoot,$queueRoot,$planRoot,$stateRoot,$receiptRoot,$busRoot) | ForEach-Object {
    $null = New-Item -ItemType Directory -Force -Path $_
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$scheduleId = "VXN-SCHED-$stamp"

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
        } catch {}

        return $Default
    }

    $p = $Object.PSObject.Properties[$Name]

    if ($null -eq $p -or $null -eq $p.Value) {
        return $Default
    }

    return $p.Value
}

function Get-RosterState {
    param($Roster,[string]$Role)

    if ($null -eq $Roster) { return 'UNKNOWN' }

    $field = Get-Prop $Roster 'field_roster' $null
    $members = @()

    if ($null -ne $field) {
        $members = @(Get-Prop $field 'members' @())
    }
    else {
        $members = @(Get-Prop $Roster 'members' @())
    }

    $m = $members |
        Where-Object { [string](Get-Prop $_ 'display_name' '') -eq $Role } |
        Select-Object -First 1

    if ($null -eq $m) { return 'UNKNOWN' }

    return [string](Get-Prop $m 'roster_state' 'UNKNOWN')
}

function Get-RolePriority {
    param(
        [string]$Role,
        [string]$MissionClass,
        [string]$RosterState,
        [double]$FormationScore
    )

    $missionBase = switch ($MissionClass) {
        'TRANSACTION_SAFETY' {
            switch ($Role) {
                'ScopeGuard' { 100 }
                'Critic'     { 95 }
                'Verifier'   { 92 }
                'Planner'    { 85 }
                'Explorer'   { 55 }
                'Optimizer'  { 45 }
                default      { 50 }
            }
        }
        'CODING' {
            switch ($Role) {
                'Planner'    { 100 }
                'Optimizer'  { 95 }
                'Verifier'   { 90 }
                'Critic'     { 85 }
                'ScopeGuard' { 70 }
                'Explorer'   { 65 }
                default      { 50 }
            }
        }
        'MEMORY_RECALL' {
            switch ($Role) {
                'Explorer'   { 100 }
                'Verifier'   { 95 }
                'ScopeGuard' { 80 }
                'Planner'    { 75 }
                'Critic'     { 70 }
                default      { 50 }
            }
        }
        'UI_LOCK_SCOPE' {
            switch ($Role) {
                'ScopeGuard' { 100 }
                'Planner'    { 90 }
                'Critic'     { 85 }
                'Verifier'   { 80 }
                default      { 50 }
            }
        }
        'REVIEW' {
            switch ($Role) {
                'Verifier'   { 100 }
                'Critic'     { 100 }
                'ScopeGuard' { 90 }
                'Planner'    { 70 }
                default      { 50 }
            }
        }
        default {
            switch ($Role) {
                'Planner'    { 95 }
                'Critic'     { 90 }
                'ScopeGuard' { 90 }
                'Explorer'   { 85 }
                'Verifier'   { 85 }
                'Optimizer'  { 75 }
                default      { 50 }
            }
        }
    }

    $rosterBoost = switch ($RosterState) {
        'STARTER' { 12 }
        'BENCH'   { 4 }
        'RESERVE' { -4 }
        'TRIAL'   { -8 }
        default   { 0 }
    }

    $formationBoost = [int][math]::Round(
        [math]::Min(15.0,[math]::Max(0.0,$FormationScore * 15.0))
    )

    return $missionBase + $rosterBoost + $formationBoost
}

function Get-LatestStableWidth {
    param($Formation,$ParallelMemory)

    $formationParty = Get-Prop $Formation 'party' $null
    $formationWidth = [int](Get-Prop $formationParty 'physical_parallel_width' 1)

    $memoryWidth = 0
    if ($null -ne $ParallelMemory) {
        $memoryWidth = [int](Get-Prop $ParallelMemory 'last_proven_stable_width' 0)
    }

    if ($memoryWidth -gt 0) {
        return [math]::Min($formationWidth,$memoryWidth)
    }

    return [math]::Max(1,$formationWidth)
}

function Get-CommandSpecialty {
    param(
        $SpecialtyIndex,
        [string]$MissionClass,
        [string]$DefaultModel
    )

    if ($null -eq $SpecialtyIndex) {
        return [pscustomobject]@{
            Model=$DefaultModel
            SpecialtyScore=0
            Confidence='PROVISIONAL'
        }
    }

    $entries = @(Get-Prop $SpecialtyIndex 'mission_index' @())

    $entry = $entries |
        Where-Object { [string](Get-Prop $_ 'mission_class' '') -eq $MissionClass } |
        Select-Object -First 1

    if ($null -eq $entry) {
        return [pscustomobject]@{
            Model=$DefaultModel
            SpecialtyScore=0
            Confidence='PROVISIONAL'
        }
    }

    $model = [string](Get-Prop $entry 'best_command_model' $DefaultModel)

    if ([string]::IsNullOrWhiteSpace($model)) {
        $model = $DefaultModel
    }

    return [pscustomobject]@{
        Model=$model
        SpecialtyScore=[double](Get-Prop $entry 'best_specialty_score' 0)
        Confidence=[string](Get-Prop $entry 'confidence' 'PROVISIONAL')
    }
}

function Group-IntoWaves {
    param(
        [array]$Tasks,
        [int]$Width,
        [bool]$PreferResidency
    )

    $working = @($Tasks)

    if ($PreferResidency) {
        $working = @(
            $working |
            Sort-Object `
                @{Expression={ [string](Get-Prop $_ 'model' '') }; Descending=$false},
                @{Expression={ [int](Get-Prop $_ 'priority' 0) }; Descending=$true}
        )
    }
    else {
        $working = @(
            $working |
            Sort-Object `
                @{Expression={ [int](Get-Prop $_ 'priority' 0) }; Descending=$true}
        )
    }

    $waves = @()
    $index = 0
    $waveNo = 0

    while ($index -lt $working.Count) {
        $waveNo++

        $take = [math]::Min($Width,$working.Count - $index)
        $items = @()

        for ($i=0; $i -lt $take; $i++) {
            $items += $working[$index + $i]
        }

        $models = @(
            $items |
            ForEach-Object { $_.model } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
        )

        $waves += [ordered]@{
            wave=$waveNo
            width=$items.Count
            tasks=$items
            models=$models
            residency_hint=if ($models.Count -eq 1) {
                'KEEP_MODEL_RESIDENT'
            } else {
                'MIXED_MODEL_WAVE'
            }
        }

        $index += $take
    }

    return $waves
}

Banner 'VERTEX — ADAPTIVE MISSION SCHEDULER V0.1.1'

$formation = Read-JsonSafe $formationPath
$roster = Read-JsonSafe $rosterPath
$commandStaff = Read-JsonSafe $commandStaffPath
$commandSpecialty = Read-JsonSafe $commandSpecialtyPath
$parallelMemory = Read-JsonSafe $parallelMemoryPath

if ($null -eq $formation) {
    throw "Formation plan not found: $formationPath"
}

$formationId = [string](Get-Prop $formation 'formation_id' 'UNKNOWN')

$mission = Get-Prop $formation 'mission' $null
$missionClass = [string](Get-Prop $mission 'class' 'GENERAL')

$party = Get-Prop $formation 'party' $null
$roles = @(Get-Prop $party 'roles' @())

$command = Get-Prop $formation 'command' $null
$defaultIntegrator = [string](Get-Prop $command 'integrator_model' '')

$stableWidth = Get-LatestStableWidth `
    -Formation $formation `
    -ParallelMemory $parallelMemory

if ($MaxWaveSize -gt 0) {
    $stableWidth = [math]::Min($stableWidth,$MaxWaveSize)
}

if ($stableWidth -lt 1) { $stableWidth = 1 }

$specialty = Get-CommandSpecialty `
    -SpecialtyIndex $commandSpecialty `
    -MissionClass $missionClass `
    -DefaultModel $defaultIntegrator

Write-Host "Schedule ID    : $scheduleId"
Write-Host "Formation ID   : $formationId"
Write-Host "Mission Class  : $missionClass"
Write-Host "Logical Party  : $($roles.Count)"
Write-Host "Stable Width   : $stableWidth"
Write-Host "Command Model  : $($specialty.Model)"

$tasks = @()

foreach ($role in $roles) {
    $roleName = [string](Get-Prop $role 'role' 'Agent')
    $model = [string](Get-Prop $role 'model' '')
    $formationScore = [double](Get-Prop $role 'formation_score' 0)
    $assignmentStatus = [string](Get-Prop $role 'assignment_status' 'EXPERIENCED')

    $rosterState = Get-RosterState -Roster $roster -Role $roleName

    $priority = Get-RolePriority `
        -Role $roleName `
        -MissionClass $missionClass `
        -RosterState $rosterState `
        -FormationScore $formationScore

    $tasks += [ordered]@{
        task_id="$formationId::$roleName"
        role=$roleName
        model=$model
        roster_state=$rosterState
        assignment_status=$assignmentStatus
        formation_score=$formationScore
        priority=$priority
        state='QUEUED'
    }
}

$waves = Group-IntoWaves `
    -Tasks $tasks `
    -Width $stableWidth `
    -PreferResidency $PreferModelResidency

$priorityOrdered = @(
    $tasks |
    Sort-Object @{Expression={ [int](Get-Prop $_ 'priority' 0) }; Descending=$true}
)

$highestPriorityRole = ''
$wave1Roles = @()
$priorityOrderingGreen = $true

if ($priorityOrdered.Count -gt 0) {
    $highestPriorityRole = [string](Get-Prop $priorityOrdered[0] 'role' '')
}

if ($waves.Count -gt 0) {
    $wave1Roles = @(
        (Get-Prop $waves[0] 'tasks' @()) |
        ForEach-Object { [string](Get-Prop $_ 'role' '') }
    )
}

if (
    -not [string]::IsNullOrWhiteSpace($highestPriorityRole) -and
    ($wave1Roles -notcontains $highestPriorityRole)
) {
    $priorityOrderingGreen = $false
}


$queue = [ordered]@{
    schema='vertex.scheduler.mission-queue.v1.1'
    schedule_id=$scheduleId
    formation_id=$formationId
    mission_class=$missionClass
    created_at=(Get-Date).ToString('o')
    queue=@($tasks | Sort-Object @{Expression={ [int](Get-Prop $_ 'priority' 0) }; Descending=$true})
}

$queuePath = Join-Path $queueRoot "$scheduleId.QUEUE.json"
Write-Json $queuePath $queue

$commandPhase = [ordered]@{
    phase='COMMAND_INTEGRATION'
    order=($waves.Count + 1)
    model=$specialty.Model
    specialty_score=$specialty.SpecialtyScore
    confidence=$specialty.Confidence
    trigger='AFTER_FIELD_WAVES_COMPLETE'
    execution_mode='SERIAL'
}

$plan = [ordered]@{
    schema='vertex.scheduler.adaptive-mission-plan.v1.1'
    schedule_id=$scheduleId
    formation_id=$formationId
    mission_class=$missionClass
    generated_at=(Get-Date).ToString('o')

    scheduler=[ordered]@{
        logical_party_size=$roles.Count
        physical_parallel_width=$stableWidth
        prefer_model_residency=$PreferModelResidency
        queue_policy='PRIORITY_PLUS_MODEL_RESIDENCY'
        retry_policy='FAILED_TASKS_ONLY'
        http_500_backoff='DECREMENT_WIDTH_BY_1'
        minimum_width=1
        probe_up_after_success=$true
        priority_ordering_green=$priorityOrderingGreen
        highest_priority_role=$highestPriorityRole
    }

    field_execution=[ordered]@{
        waves=$waves
    }

    command_execution=$commandPhase

    runtime_hints=[ordered]@{
        keep_same_model_loaded_when_possible=$PreferModelResidency
        release_model_between_model_families=$true
        observe_http_500=$true
        observe_latency=$true
        observe_queue_depth=$true
        observe_runtime_capacity=$true
        allow_runtime_backoff=$true
    }

    execution_policy=[ordered]@{
        automatic_execution=$false
        requires_go_signal=$true
        scheduler_is_authoritative_for_order=$true
        executor_is_authoritative_for_actual_runtime_result=$true
    }

    safety=[ordered]@{
        canonical_mutation='NONE'
        vtc_execution='NONE'
        model_invocation='NONE'
        agent_execution='NONE'
    }
}

$planPath = Join-Path $planRoot "$scheduleId.PLAN.json"
$currentPlanPath = Join-Path $planRoot 'CURRENT_SCHEDULE_PLAN.json'
Write-Json $planPath $plan
Write-Json $currentPlanPath $plan

$busHandoff = [ordered]@{
    schema='vertex.load-balancing-bus.handoff.v1.1'
    schedule_id=$scheduleId
    mission_class=$missionClass

    routes=@(
        $waves |
        ForEach-Object {
            [ordered]@{
                route_id="WAVE-$($_.wave)"
                wave=$_.wave
                requested_width=$_.width
                models=$_.models
                tasks=@(
                    $_.tasks |
                    ForEach-Object {
                        [ordered]@{
                            task_id=$_.task_id
                            role=$_.role
                            model=$_.model
                            priority=$_.priority
                        }
                    }
                )
            }
        }
    )

    command_route=[ordered]@{
        route_id='COMMAND'
        model=$specialty.Model
        trigger='FIELD_COMPLETE'
    }

    capacity_contract=[ordered]@{
        initial_width=$stableWidth
        minimum_width=1
        reduce_on_http_500=$true
        probe_up_after_stable_wave=$true
    }

    state='READY_FOR_LOAD_BALANCING_BUS'
}

$busPath = Join-Path $busRoot "$scheduleId.BUS_HANDOFF.json"
$currentBusPath = Join-Path $busRoot 'CURRENT_BUS_HANDOFF.json'
Write-Json $busPath $busHandoff
Write-Json $currentBusPath $busHandoff

$state = [ordered]@{
    schema='vertex.scheduler.current-state.v1'
    updated_at=(Get-Date).ToString('o')
    schedule_id=$scheduleId
    state='PLANNED'
    mission_class=$missionClass
    formation_id=$formationId
    physical_width=$stableWidth
    waves=$waves.Count
    command_model=$specialty.Model
}

$statePath = Join-Path $stateRoot 'CURRENT_SCHEDULER_STATE.json'
Write-Json $statePath $state

$receiptPath = Join-Path $receiptRoot "$scheduleId.RECEIPT.json"

Write-Json $receiptPath ([ordered]@{
    schema='vertex.scheduler.plan-receipt.v1.1'
    completed_at=(Get-Date).ToString('o')
    schedule_id=$scheduleId
    formation_id=$formationId
    mission_class=$missionClass
    wave_count=$waves.Count
    physical_width=$stableWidth
    command_model=$specialty.Model
    priority_ordering_green=$priorityOrderingGreen
    highest_priority_role=$highestPriorityRole
    schedule_plan=$planPath
    bus_handoff=$busPath
    automatic_execution=$false
    canonical_mutation='NONE'
    vtc_execution='NONE'
    model_invocation='NONE'
    agent_execution='NONE'
})

Write-Host ''
Write-Host '[MISSION QUEUE]' -ForegroundColor Cyan

foreach ($t in ($tasks | Sort-Object @{Expression={ [int](Get-Prop $_ 'priority' 0) }; Descending=$true})) {
    Write-Host (
        "  priority={0,-4} role={1,-14} roster={2,-8} model={3}" -f `
        $t.priority,
        $t.role,
        $t.roster_state,
        $t.model
    )
}

Write-Host ''
Write-Host '[WAVE SCHEDULE]' -ForegroundColor Cyan

foreach ($w in $waves) {
    Write-Host (
        "  WAVE {0} width={1} residency={2}" -f `
        $w.wave,
        $w.width,
        $w.residency_hint
    )

    foreach ($t in $w.tasks) {
        Write-Host (
            "      {0,-14} model={1} priority={2}" -f `
            $t.role,
            $t.model,
            $t.priority
        )
    }
}

Write-Host ''
Write-Host '[COMMAND PHASE]' -ForegroundColor Cyan
Write-Host "  Model       : $($specialty.Model)"
Write-Host "  Specialty   : $($specialty.SpecialtyScore)"
Write-Host "  Confidence  : $($specialty.Confidence)"
Write-Host "  Trigger     : FIELD_COMPLETE"

Write-Host ''
Write-Host '[SCHEDULER VALIDATION]' -ForegroundColor Cyan
Write-Host "  Highest Priority : $highestPriorityRole"
Write-Host "  Wave 1 Roles     : $($wave1Roles -join ', ')"
Write-Host "  Priority Ordering: $(if ($priorityOrderingGreen) { 'GREEN' } else { 'RED' })"

Write-Host ''
Write-Host '[LOAD BALANCING BUS HANDOFF]' -ForegroundColor Cyan
Write-Host "  Routes      : $($waves.Count)"
Write-Host "  Width       : $stableWidth"
Write-Host "  State       : READY_FOR_LOAD_BALANCING_BUS"

Write-Host ''
Write-Host "Queue        : $queuePath"
Write-Host "Schedule     : $planPath"
Write-Host "Current      : $currentPlanPath"
Write-Host "Bus Handoff  : $busPath"
Write-Host "State        : $statePath"
Write-Host "Receipt      : $receiptPath"

Write-Host ''
Write-Host 'AUTO EXECUTION      : DISABLED'
Write-Host 'GO SIGNAL REQUIRED  : YES'
Write-Host 'CANONICAL MUTATION  : NONE'
Write-Host 'VTC EXECUTION       : NONE'
Write-Host 'MODEL INVOCATION    : NONE'
Write-Host 'AGENT EXECUTION     : NONE'
Write-Host ''
Write-Host 'VERTEX ADAPTIVE MISSION SCHEDULER READY.'
Write-Host '轟。' -ForegroundColor Green
