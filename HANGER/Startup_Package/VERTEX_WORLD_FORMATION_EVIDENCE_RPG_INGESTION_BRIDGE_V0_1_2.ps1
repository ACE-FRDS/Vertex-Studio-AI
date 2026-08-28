#requires -Version 7.0
<#
VERTEX WORLD — FORMATION EVIDENCE RPG INGESTION BRIDGE V0.1.2

PURPOSE
  Convert ARD Formation Executor receipts into RPG battle logs that are
  consumable by existing Vertex World progression / synergy / confidence layers.

PIPELINE
  Formation Executor Receipt
      -> RPG Battle Log
      -> Progression refresh
      -> Synergy/Affinity refresh
      -> Confidence refresh
      -> Auto Formation refresh

SAFETY
  - No model invocation.
  - No agent execution.
  - No canonical mutation.
  - No VTC execution.
  - Writes only Vertex World runtime/receipt artifacts.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'G:\Vertex_Project\Vertex_Studio_AI',
    [string]$VxnRoot = '',
    [bool]$RefreshDownstream = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VxnRoot)) {
    $VxnRoot = Join-Path $ProjectRoot 'VXN'
}

$formationExecRoot = Join-Path $VxnRoot 'experiments\formation_executor'
$rpgRoot = Join-Path $VxnRoot 'runtime\rpg'
$battleRoot = Join-Path $rpgRoot 'battle_logs'
$ingestRoot = Join-Path $rpgRoot 'ingestion'
$receiptRoot = Join-Path $rpgRoot 'receipts'

$hangerRoot = Join-Path $ProjectRoot 'HANGER\Startup_Package'

@($battleRoot,$ingestRoot,$receiptRoot) | ForEach-Object {
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
    if ($parent) {
        $null = New-Item -ItemType Directory -Force -Path $parent
    }

    $Object | ConvertTo-Json -Depth 100 |
        Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-Prop {
    param(
        $Object,
        [string]$Name,
        $Default=$null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $p = $Object.PSObject.Properties[$Name]

    if ($null -eq $p -or $null -eq $p.Value) {
        return $Default
    }

    return $p.Value
}

function Get-RoleClass([string]$Role) {
    switch -Regex ($Role) {
        '^Explorer$'   { return 'SCOUT' }
        '^Planner$'    { return 'TACTICIAN' }
        '^Critic$'     { return 'ANALYST' }
        '^ScopeGuard$' { return 'GUARDIAN' }
        '^Verifier$'   { return 'VERIFIER' }
        '^Optimizer$'  { return 'ENGINEER' }
        default        { return 'AGENT' }
    }
}

function Get-ModelTier([string]$Model) {
    if ($Model -match '(?i)(30|32|34)b') { return '30B' }
    if ($Model -match '(?i)(12|13|14)b') { return '12B' }
    if ($Model -match '(?i)(7|8|9)b') { return '8B' }
    if ($Model -match '(?i)(3|4)b') { return '3B4B' }
    return 'UNKNOWN'
}

function Get-SpeedIndex([double]$LatencyMs) {
    if ($LatencyMs -le 0) { return 50 }
    if ($LatencyMs -lt 5000) { return 100 }
    if ($LatencyMs -lt 7000) { return 92 }
    if ($LatencyMs -lt 10000) { return 82 }
    if ($LatencyMs -lt 15000) { return 70 }
    if ($LatencyMs -lt 22000) { return 55 }
    return 40
}

function Get-LatestDownstreamScript {
    param([string]$Pattern)

    if (-not (Test-Path -LiteralPath $hangerRoot)) {
        return $null
    }

    return Get-ChildItem -LiteralPath $hangerRoot -File -Filter $Pattern |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

function Invoke-DownstreamScript {
    param(
        [string]$Label,
        $ScriptFile,
        [hashtable]$Arguments=@{}
    )

    if ($null -eq $ScriptFile) {
        Write-Host "  SKIP  : $Label — script not found." -ForegroundColor Yellow
        return [pscustomobject]@{
            label=$Label
            status='SKIPPED_NOT_FOUND'
            path=''
        }
    }

    Write-Host "  RUN   : $Label"
    Write-Host "          $($ScriptFile.FullName)"

    try {
        # PowerShell script invocation does not reliably set $LASTEXITCODE.
        # Under StrictMode, reading an unset $LASTEXITCODE throws.
        # Therefore success is determined by whether the script invocation throws.
        & $ScriptFile.FullName @Arguments

        return [pscustomobject]@{
            label=$Label
            status='GREEN'
            path=$ScriptFile.FullName
        }
    }
    catch {
        Write-Host "  ERROR : $Label — $($_.Exception.Message)" -ForegroundColor Red

        return [pscustomobject]@{
            label=$Label
            status='ERROR'
            path=$ScriptFile.FullName
            error=$_.Exception.Message
        }
    }
}

Banner 'VERTEX WORLD — FORMATION EVIDENCE RPG INGESTION BRIDGE V0.1.2'

if (-not (Test-Path -LiteralPath $formationExecRoot)) {
    throw "Formation executor experiment directory not found: $formationExecRoot"
}

$receiptFiles = @(
    Get-ChildItem `
        -LiteralPath $formationExecRoot `
        -Recurse `
        -File `
        -Filter 'VERTEX_ARD_FORMATION_EXECUTION_RECEIPT.json' |
    Sort-Object LastWriteTime
)

if ($receiptFiles.Count -eq 0) {
    throw 'No Formation Executor receipts found.'
}

Write-Host "Formation Receipts : $($receiptFiles.Count)"

$ingested = New-Object System.Collections.Generic.List[object]
$skipped = New-Object System.Collections.Generic.List[object]

$latestMissionClass = 'GENERAL'

Write-Host ''
Write-Host '[1/4] INGEST FORMATION RECEIPTS'

foreach ($file in $receiptFiles) {
    $receipt = Read-JsonSafe $file.FullName

    if ($null -eq $receipt) {
        Write-Host "  SKIP : unreadable $($file.FullName)" -ForegroundColor Yellow
        continue
    }

    $runId = [string](Get-Prop $receipt 'run_id' $file.Directory.Name)
    $formationId = [string](Get-Prop $receipt 'formation_id' '')
    $missionClass = [string](Get-Prop $receipt 'mission_class' 'GENERAL')
    $latestMissionClass = $missionClass

    $battlePath = Join-Path $battleRoot "$runId.RPG_BATTLE_LOG.json"

    if (Test-Path -LiteralPath $battlePath) {
        Write-Host "  KEEP : $runId already ingested; downstream refresh may still run."
        $skipped.Add([pscustomobject]@{
            run_id=$runId
            source=$file.FullName
            battle_log=$battlePath
            reason='ALREADY_INGESTED'
        })
        continue
    }

    $party = Get-Prop $receipt 'party' $null
    $partyResults = @(Get-Prop $party 'results' @())
    $logicalSize = [int](Get-Prop $party 'logical_size' $partyResults.Count)
    $plannedWidth = [int](Get-Prop $party 'planned_width' 1)
    $stableWidth = [int](Get-Prop $party 'stable_width' $plannedWidth)

    $characters = @()

    foreach ($r in $partyResults) {
        $role = [string](Get-Prop $r 'Role' (Get-Prop $r 'role' 'Agent'))
        $model = [string](Get-Prop $r 'Model' (Get-Prop $r 'model' ''))
        $success = [bool](Get-Prop $r 'Success' (Get-Prop $r 'success' $false))
        $latency = [double](Get-Prop $r 'LatencyMs' (Get-Prop $r 'latency_ms' 0))
        $assignment = [string](Get-Prop $r 'AssignmentStatus' (Get-Prop $r 'assignment_status' 'EXPERIENCED'))

        $characters += [ordered]@{
            character_id="ARD-$role"
            display_name=$role
            class=(Get-RoleClass $role)
            model=$model
            model_tier=(Get-ModelTier $model)
            assignment_status=$assignment
            status=if ($success) { 'READY' } else { 'RECOVERY' }

            measured_stats=[ordered]@{
                speed_index=(Get-SpeedIndex $latency)
                reliability_index=if ($success) { 85 } else { 25 }
                latency_ms=$latency
            }

            rookie_evidence=[ordered]@{
                was_trial=($assignment -eq 'TRIAL_ASSIGNMENT')
                trial_completed=($assignment -eq 'TRIAL_ASSIGNMENT')
                trial_success=($assignment -eq 'TRIAL_ASSIGNMENT' -and $success)
            }
        }
    }

    $integrator = Get-Prop $receipt 'integrator' $null
    $integratorModel = [string](Get-Prop $integrator 'model' '')
    $integratorGreen = [bool](Get-Prop $integrator 'green' $false)
    $integratorScore = [double](Get-Prop $integrator 'score' 0)

    $escalation = Get-Prop $receipt 'escalation' $null
    $escalationUsed = [bool](Get-Prop $escalation 'used' $false)
    $finalModel = [string](Get-Prop $escalation 'final_model' $integratorModel)

    $final = Get-Prop $receipt 'final' $null
    $finalGreen = [bool](Get-Prop $final 'green' $false)
    $finalScore = [double](Get-Prop $final 'score' 0)

    $rookies = @(Get-Prop $receipt 'rookies' @())

    $events = @()

    $events += [ordered]@{
        event='FORMATION_DEPLOYED'
        formation_id=$formationId
        mission_class=$missionClass
        logical_party_size=$logicalSize
        planned_width=$plannedWidth
        rpg_message="Formation $formationId deployed."
    }

    if ($stableWidth -lt $plannedWidth) {
        $events += [ordered]@{
            event='RUNTIME_BACKOFF'
            planned_width=$plannedWidth
            stable_width=$stableWidth
            rpg_message="Runtime adjusted physical width from $plannedWidth to $stableWidth."
        }
    }
    else {
        $events += [ordered]@{
            event='FORMATION_STABLE'
            stable_width=$stableWidth
            rpg_message="Formation remained stable at width $stableWidth."
        }
    }

    foreach ($rookie in $rookies) {
        $rookieRole = [string](Get-Prop $rookie 'role' '')
        $rookieModel = [string](Get-Prop $rookie 'model' '')
        $rookieSuccess = [bool](Get-Prop $rookie 'success' $false)

        $events += [ordered]@{
            event='ROOKIE_TRIAL_COMPLETE'
            role=$rookieRole
            model=$rookieModel
            success=$rookieSuccess
            rpg_message=if ($rookieSuccess) {
                "Rookie $rookieRole completed first field trial successfully."
            } else {
                "Rookie $rookieRole completed field trial with recovery required."
            }
        }
    }

    if ($integratorGreen) {
        $events += [ordered]@{
            event='INTEGRATION_GREEN'
            model=$integratorModel
            score=$integratorScore
            rpg_message='Formation outputs integrated successfully.'
        }
    }
    else {
        $events += [ordered]@{
            event='INTEGRATION_NOT_GREEN'
            model=$integratorModel
            score=$integratorScore
            rpg_message='Integrator requested support.'
        }
    }

    if ($escalationUsed) {
        $events += [ordered]@{
            event='SUPPORT_SUMMON'
            model=$finalModel
            model_tier=(Get-ModelTier $finalModel)
            rpg_message='Senior support entered the formation mission.'
        }
    }

    $partyModel = ''

    if ($characters.Count -gt 0) {
        $models = @(
            $characters |
            ForEach-Object { [string]$_.model } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
        )

        if ($models.Count -eq 1) {
            $partyModel = $models[0]
        }
        elseif ($models.Count -gt 1) {
            $partyModel = 'MIXED_FORMATION'
        }
    }

    $battleLog = [ordered]@{
        schema='vertex.world.rpg.execution-log.v1.1'
        run_id=$runId
        formation_id=$formationId
        source_receipt=$file.FullName
        mission_class=$missionClass
        mission_result=if ($finalGreen) { 'MISSION_CLEAR' } else { 'MISSION_HOLD' }
        final_score=$finalScore

        party=[ordered]@{
            logical_size=$logicalSize
            model=$partyModel
            tier=if ($partyModel -eq 'MIXED_FORMATION') { 'MIXED' } else { Get-ModelTier $partyModel }
            stable_physical_width=$stableWidth
            next_probe_width=[math]::Min($logicalSize,$stableWidth + 1)
            characters=$characters
        }

        command=[ordered]@{
            integrator=$integratorModel
            integrator_green=$integratorGreen
            escalation_used=$escalationUsed
            final_model=$finalModel
        }

        rookies=$rookies
        events=$events

        safety=[ordered]@{
            canonical_mutation='NONE'
            vtc_execution='NONE'
        }
    }

    Write-Json $battlePath $battleLog

    Write-Host "  WRITE: $runId -> RPG Battle Log"
    Write-Host "         Mission=$missionClass Clear=$finalGreen StableWidth=$stableWidth Rookies=$($rookies.Count)"

    $ingested.Add([pscustomobject]@{
        run_id=$runId
        mission_class=$missionClass
        source=$file.FullName
        battle_log=$battlePath
        clear=$finalGreen
        stable_width=$stableWidth
        rookies=$rookies.Count
    })
}

$ingestionIndexPath = Join-Path $ingestRoot 'FORMATION_EVIDENCE_INGESTION_INDEX.json'

Write-Json $ingestionIndexPath ([ordered]@{
    schema='vertex.world.rpg.formation-evidence-ingestion.v1.2'
    updated_at=(Get-Date).ToString('o')
    formation_receipts_found=$receiptFiles.Count
    ingested=@($ingested.ToArray())
    skipped=@($skipped.ToArray())
})

Write-Host ''
Write-Host '[2/4] INGESTION SUMMARY'
Write-Host "  New Battle Logs : $($ingested.Count)"
Write-Host "  Already Present : $($skipped.Count)"
Write-Host "  Index           : $ingestionIndexPath"

$refreshResults = @()

Write-Host ''
Write-Host '[3/4] DOWNSTREAM REFRESH'

if ($RefreshDownstream) {
    $progressionScript = Get-LatestDownstreamScript 'VERTEX_WORLD_RPG_PROGRESSION_ENGINE_V*.ps1'
    $synergyScript = Get-LatestDownstreamScript 'VERTEX_WORLD_RPG_SYNERGY_AFFINITY_ENGINE_V*.ps1'
    $confidenceScript = Get-LatestDownstreamScript 'VERTEX_WORLD_AFFINITY_CONFIDENCE_LAYER_V*.ps1'
    $commandStaffScript = Get-LatestDownstreamScript 'VERTEX_WORLD_COMMAND_STAFF_EVIDENCE_ENGINE_V*.ps1'
    $commandSpecialtyScript = Get-LatestDownstreamScript 'VERTEX_WORLD_COMMAND_SPECIALTY_ENGINE_V*.ps1'
    $rosterScript = Get-LatestDownstreamScript 'VERTEX_WORLD_ROSTER_LIFECYCLE_ENGINE_V*.ps1'
    $formationScript = Get-LatestDownstreamScript 'VERTEX_WORLD_AUTO_PARTY_FORMATION_ENGINE_V*.ps1'
    $schedulerScript = Get-LatestDownstreamScript 'VERTEX_ADAPTIVE_MISSION_SCHEDULER_V*.ps1'
    $busScript = Get-LatestDownstreamScript 'VERTEX_LOAD_BALANCING_BUS_V*.ps1'

    $refreshResults += Invoke-DownstreamScript `
        -Label 'RPG Progression' `
        -ScriptFile $progressionScript

    $refreshResults += Invoke-DownstreamScript `
        -Label 'Synergy / Affinity' `
        -ScriptFile $synergyScript

    $refreshResults += Invoke-DownstreamScript `
        -Label 'Affinity Confidence' `
        -ScriptFile $confidenceScript

    $refreshResults += Invoke-DownstreamScript `
        -Label 'Command Staff Evidence' `
        -ScriptFile $commandStaffScript

    $refreshResults += Invoke-DownstreamScript `
        -Label 'Command Specialty' `
        -ScriptFile $commandSpecialtyScript

    $refreshResults += Invoke-DownstreamScript `
        -Label 'Roster Lifecycle' `
        -ScriptFile $rosterScript

    $formationArgs = @{
        MissionClass=$latestMissionClass
    }

    $refreshResults += Invoke-DownstreamScript `
        -Label 'Auto Party Formation' `
        -ScriptFile $formationScript `
        -Arguments $formationArgs

    $refreshResults += Invoke-DownstreamScript `
        -Label 'Adaptive Scheduler' `
        -ScriptFile $schedulerScript

    $refreshResults += Invoke-DownstreamScript `
        -Label 'Load Balancing Bus' `
        -ScriptFile $busScript
}
else {
    Write-Host '  RefreshDownstream=False — ingestion only.'
}

Write-Host ''
Write-Host '[4/4] BRIDGE RECEIPT'

$bridgeReceiptPath = Join-Path $receiptRoot "FORMATION_EVIDENCE_INGESTION.$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"

Write-Json $bridgeReceiptPath ([ordered]@{
    schema='vertex.world.rpg.formation-evidence-ingestion-receipt.v1.2'
    completed_at=(Get-Date).ToString('o')
    receipts_found=$receiptFiles.Count
    newly_ingested=$ingested.Count
    already_ingested=$skipped.Count
    downstream_refresh=$RefreshDownstream
    downstream_results=$refreshResults
    planning_loop_refreshed=$RefreshDownstream
    ingestion_index=$ingestionIndexPath
    canonical_mutation='NONE'
    vtc_execution='NONE'
    agent_execution='NONE'
})

Write-Host "  Receipt : $bridgeReceiptPath"

Banner 'VERTEX WORLD — FORMATION EVIDENCE INGESTION COMPLETE'

Write-Host "Formation Receipts : $($receiptFiles.Count)"
Write-Host "New RPG Battles    : $($ingested.Count)"
Write-Host "Already Ingested   : $($skipped.Count)"
Write-Host "Latest Mission     : $latestMissionClass"
Write-Host "Refresh Downstream : $RefreshDownstream"

if ($RefreshDownstream -and $refreshResults.Count -gt 0) {
    Write-Host ''
    Write-Host '[REFRESH STATUS]' -ForegroundColor Cyan

    foreach ($r in $refreshResults) {
        Write-Host ("  {0,-24} {1}" -f $r.label,$r.status)
    }
}

Write-Host ''
Write-Host 'FORMATION EVIDENCE IS NOW PART OF VERTEX WORLD HISTORY.'
Write-Host 'CANONICAL MUTATION : NONE'
Write-Host 'VTC EXECUTION      : NONE'
Write-Host 'AGENT EXECUTION    : NONE'
Write-Host ''
Write-Host 'VERTEX WORLD — LEARNING + PLANNING LOOP CLOSED.'
Write-Host '轟。' -ForegroundColor Green
