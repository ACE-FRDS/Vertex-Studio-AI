#requires -Version 7.0
<#
VERTEX ENV-2 V2.6 — TRANSACTION FIREWALL EXECUTOR
ONE CANDIDATE / ONE TRANSACTION / VERIFY EACH STEP / AUTO ROLLBACK ON FAILURE

SAFETY MODEL
  - Default mode is DryRun
  - Execute requires explicit CandidateId and approval token
  - Loads latest PREPARED transaction package from V2.5
  - Revalidates exact live firewall fingerprints before mutation
  - Removes only the exact rule identities in the prepared manifest
  - Verifies removal immediately
  - On any failure, attempts rollback from stored rule snapshots
  - Emits execution + rollback receipts
  - Never operates on rules outside the selected candidate

IMPORTANT
  This is the first ENV-2 stage that CAN mutate Windows Firewall state.
#>

[CmdletBinding()]
param(
    [ValidateSet('DryRun','Execute')]
    [string]$Mode = 'DryRun',

    [Parameter(Mandatory)]
    [string]$CandidateId,

    [string]$Approval = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$TxnRoot = Join-Path $ReportRoot '_transactions'

function Get-SafeProperty {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $Default }
    if ($null -eq $p.Value) { return $Default }
    return $p.Value
}

function Normalize-ProgramPath {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return $Path.Trim().Trim('"').Replace('/','\').ToLowerInvariant()
}

function Get-RuleSnapshot {
    param([Parameter(Mandatory)]$Rule)

    $app = $Rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
    $port = $Rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
    $addr = $Rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
    $svc  = $Rule | Get-NetFirewallServiceFilter -ErrorAction SilentlyContinue

    return [pscustomobject][ordered]@{
        name                     = [string]$Rule.Name
        display_name             = [string]$Rule.DisplayName
        description              = [string]$Rule.Description
        group                    = [string]$Rule.Group
        enabled                  = [string]$Rule.Enabled
        profile                  = [string]$Rule.Profile
        direction                = [string]$Rule.Direction
        action                   = [string]$Rule.Action
        edge_traversal_policy    = [string]$Rule.EdgeTraversalPolicy
        policy_store_source      = [string]$Rule.PolicyStoreSource
        policy_store_source_type = [string]$Rule.PolicyStoreSourceType

        application = [ordered]@{
            program = [string](Get-SafeProperty -Object $app -Name 'Program' -Default '')
        }

        port = [ordered]@{
            protocol    = [string](Get-SafeProperty -Object $port -Name 'Protocol' -Default '')
            local_port  = [string](Get-SafeProperty -Object $port -Name 'LocalPort' -Default '')
            remote_port = [string](Get-SafeProperty -Object $port -Name 'RemotePort' -Default '')
            icmp_type   = [string](Get-SafeProperty -Object $port -Name 'IcmpType' -Default '')
        }

        address = [ordered]@{
            local_address  = [string](Get-SafeProperty -Object $addr -Name 'LocalAddress' -Default '')
            remote_address = [string](Get-SafeProperty -Object $addr -Name 'RemoteAddress' -Default '')
        }

        service = [ordered]@{
            service = [string](Get-SafeProperty -Object $svc -Name 'Service' -Default '')
        }
    }
}

function Get-RuleFingerprint {
    param([Parameter(Mandatory)]$Snapshot)

    $canonical = [ordered]@{
        name        = $Snapshot.name
        enabled     = $Snapshot.enabled
        profile     = $Snapshot.profile
        direction   = $Snapshot.direction
        action      = $Snapshot.action
        program     = $Snapshot.application.program
        protocol    = $Snapshot.port.protocol
        local_port  = $Snapshot.port.local_port
        remote_port = $Snapshot.port.remote_port
        local_addr  = $Snapshot.address.local_address
        remote_addr = $Snapshot.address.remote_address
        service     = $Snapshot.service.service
        source      = $Snapshot.policy_store_source
    }

    $json = $canonical | ConvertTo-Json -Depth 8 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $sha = [Security.Cryptography.SHA256]::Create()

    try {
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash)).Replace('-','').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Convert-EnabledValue {
    param([string]$Value)
    if ($Value -match 'True|Enabled') { return 'True' }
    return 'False'
}

function Restore-FirewallRuleFromSnapshot {
    param(
        [Parameter(Mandatory)]$Snapshot
    )

    # Refuse to restore if exact rule name already exists.
    $existing = @(Get-NetFirewallRule -PolicyStore PersistentStore -Name ([string]$Snapshot.name) -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        throw "Rollback conflict: rule name already exists: $($Snapshot.name)"
    }

    $params = @{
        Name        = [string]$Snapshot.name
        DisplayName = [string]$Snapshot.display_name
        Direction   = [string]$Snapshot.direction
        Action      = [string]$Snapshot.action
        Enabled     = Convert-EnabledValue ([string]$Snapshot.enabled)
        Profile     = [string]$Snapshot.profile
        PolicyStore = 'PersistentStore'
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.description)) {
        $params['Description'] = [string]$Snapshot.description
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.group)) {
        $params['Group'] = [string]$Snapshot.group
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.application.program) -and
        [string]$Snapshot.application.program -ne 'Any') {
        $params['Program'] = [string]$Snapshot.application.program
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.service.service) -and
        [string]$Snapshot.service.service -ne 'Any') {
        $params['Service'] = [string]$Snapshot.service.service
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.port.protocol) -and
        [string]$Snapshot.port.protocol -ne 'Any') {
        $params['Protocol'] = [string]$Snapshot.port.protocol
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.port.local_port) -and
        [string]$Snapshot.port.local_port -ne 'Any') {
        $params['LocalPort'] = [string]$Snapshot.port.local_port
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.port.remote_port) -and
        [string]$Snapshot.port.remote_port -ne 'Any') {
        $params['RemotePort'] = [string]$Snapshot.port.remote_port
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.address.local_address) -and
        [string]$Snapshot.address.local_address -ne 'Any') {
        $params['LocalAddress'] = [string]$Snapshot.address.local_address
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.address.remote_address) -and
        [string]$Snapshot.address.remote_address -ne 'Any') {
        $params['RemoteAddress'] = [string]$Snapshot.address.remote_address
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.edge_traversal_policy)) {
        $params['EdgeTraversalPolicy'] = [string]$Snapshot.edge_traversal_policy
    }

    New-NetFirewallRule @params | Out-Null
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.6 — TRANSACTION FIREWALL EXECUTOR' -ForegroundColor Magenta
Write-Host ' PRE-FLIGHT -> APPLY -> VERIFY -> COMMIT / ROLLBACK' -ForegroundColor Magenta
Write-Host ' ONE CANDIDATE ONLY' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

if (-not (Test-Path -LiteralPath $TxnRoot)) {
    throw "Transaction root not found: $TxnRoot"
}

$txnDir = Get-ChildItem -LiteralPath $TxnRoot -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'transaction_manifest.json') } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $txnDir) {
    throw 'No prepared V2.5 transaction package found.'
}

$manifestPath = Join-Path $txnDir.FullName 'transaction_manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80

$items = @($manifest.transaction_items)
$item = @($items | Where-Object { [string]$_.candidate_id -eq $CandidateId })

if ($item.Count -ne 1) {
    throw "CandidateId must resolve to exactly one transaction item. Candidate: $CandidateId Matches: $($item.Count)"
}

$item = $item[0]

if ($Mode -eq 'Execute' -and $Approval -ne 'APPROVE-TXN-EXECUTE') {
    throw 'Execute mode requires -Approval "APPROVE-TXN-EXECUTE".'
}

Write-Host "Transaction Package : $($txnDir.FullName)"
Write-Host "Transaction ID      : $($manifest.transaction_id)"
Write-Host "Candidate            : $CandidateId"
Write-Host "Display              : $($item.display_name)"
Write-Host "Mode                 : $Mode"

$targetNames = @($item.target_rule_names)
$expectedFingerprints = @($item.expected_fingerprints)
$rollbackSnapshots = @($item.rollback_snapshot)

if ($targetNames.Count -eq 0) {
    throw 'Transaction item has no target rules.'
}

if ($targetNames.Count -ne $expectedFingerprints.Count) {
    throw 'Target rule count and fingerprint count mismatch.'
}

if ($targetNames.Count -ne $rollbackSnapshots.Count) {
    throw 'Target rule count and rollback snapshot count mismatch.'
}

$oldProgram = [string]$item.old_program
$newProgram = [string]$item.replacement_program

# ------------------------------------------------------------
# PRE-FLIGHT
# ------------------------------------------------------------
Write-Host ''
Write-Host '[1/5] PRE-FLIGHT' -ForegroundColor Cyan

$oldExists = $false
if ($oldProgram) {
    $oldExists = Test-Path -LiteralPath $oldProgram.Trim().Trim('"') -PathType Leaf -ErrorAction SilentlyContinue
}

$newExists = $false
if ($newProgram) {
    $newExists = Test-Path -LiteralPath $newProgram.Trim().Trim('"') -PathType Leaf -ErrorAction SilentlyContinue
}

if ($oldExists) {
    throw "PRE-FLIGHT DENIED: old executable exists again: $oldProgram"
}

if (-not $newExists) {
    throw "PRE-FLIGHT DENIED: replacement executable no longer exists: $newProgram"
}

$liveSnapshots = [System.Collections.Generic.List[object]]::new()

for ($i=0; $i -lt $targetNames.Count; $i++) {
    $name = [string]$targetNames[$i]
    $expected = [string]$expectedFingerprints[$i]

    $rule = @(Get-NetFirewallRule -PolicyStore PersistentStore -Name $name -ErrorAction SilentlyContinue)

    if ($rule.Count -ne 1) {
        throw "PRE-FLIGHT DENIED: rule must exist exactly once in PersistentStore: $name (found $($rule.Count))"
    }

    $snapshot = Get-RuleSnapshot -Rule $rule[0]
    $actual = Get-RuleFingerprint -Snapshot $snapshot

    if ($actual -ne $expected) {
        throw "PRE-FLIGHT DENIED: fingerprint drift detected for rule: $name"
    }

    if ((Normalize-ProgramPath ([string]$snapshot.application.program)) -ne
        (Normalize-ProgramPath $oldProgram)) {
        throw "PRE-FLIGHT DENIED: rule program no longer matches old executable: $name"
    }

    $liveSnapshots.Add($snapshot)

    Write-Host "  GREEN : $name"
}

Write-Host "  Old executable absent      : TRUE"
Write-Host "  Replacement present        : TRUE"
Write-Host "  Fingerprints exact         : TRUE"
Write-Host "  Rollback snapshots present : TRUE"

# ------------------------------------------------------------
# DRY RUN
# ------------------------------------------------------------
if ($Mode -eq 'DryRun') {
    Write-Host ''
    Write-Host '[2/5] APPLY' -ForegroundColor Cyan
    foreach ($name in $targetNames) {
        Write-Host "  DRY_RUN — REMOVE $name"
    }

    Write-Host ''
    Write-Host '[3/5] VERIFY'
    Write-Host '  DRY_RUN — verification planned'

    Write-Host ''
    Write-Host '[4/5] COMMIT / ROLLBACK'
    Write-Host '  DRY_RUN — no state change'

    Write-Host ''
    Write-Host '[5/5] RECEIPT'
    Write-Host '  DRY_RUN_GREEN'

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' V2.6 DRY RUN : GREEN' -ForegroundColor Green
    Write-Host ' FIREWALL UNCHANGED' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green

    Write-Host ''
    Write-Host 'NEXT'
    Write-Host ' Execute this one candidate with:'
    Write-Host ''
    Write-Host "  -Mode Execute -CandidateId `"$CandidateId`" -Approval `"APPROVE-TXN-EXECUTE`""
    exit 0
}

# ------------------------------------------------------------
# EXECUTE
# ------------------------------------------------------------
$executionId = 'VTXN-EXEC-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$execDir = Join-Path $txnDir.FullName $executionId
New-Item -ItemType Directory -Path $execDir -Force | Out-Null

$receiptPath = Join-Path $execDir 'execution_receipt.json'
$rollbackReceiptPath = Join-Path $execDir 'rollback_receipt.json'

$removed = [System.Collections.Generic.List[object]]::new()
$rollbackAttempted = $false
$rollbackGreen = $false
$commitGreen = $false
$failure = $null

try {
    Write-Host ''
    Write-Host '[2/5] APPLY' -ForegroundColor Yellow

    for ($i=0; $i -lt $targetNames.Count; $i++) {
        $name = [string]$targetNames[$i]
        $snapshot = $rollbackSnapshots[$i]

        # Final exact fingerprint check immediately before each mutation.
        $rule = @(Get-NetFirewallRule -PolicyStore PersistentStore -Name $name -ErrorAction SilentlyContinue)
        if ($rule.Count -ne 1) {
            throw "APPLY ABORTED: exact rule disappeared before mutation: $name"
        }

        $currentSnapshot = Get-RuleSnapshot -Rule $rule[0]
        $currentFp = Get-RuleFingerprint -Snapshot $currentSnapshot

        if ($currentFp -ne [string]$expectedFingerprints[$i]) {
            throw "APPLY ABORTED: fingerprint drift immediately before mutation: $name"
        }

        Remove-NetFirewallRule -PolicyStore PersistentStore -Name $name -ErrorAction Stop

        $after = @(Get-NetFirewallRule -PolicyStore PersistentStore -Name $name -ErrorAction SilentlyContinue)
        if ($after.Count -ne 0) {
            throw "VERIFY FAILED: rule still exists after removal: $name"
        }

        $removed.Add([pscustomobject][ordered]@{
            name = $name
            snapshot = $snapshot
            removed_at = (Get-Date).ToString('o')
        })

        Write-Host "  REMOVED + VERIFIED : $name" -ForegroundColor Green
    }

    Write-Host ''
    Write-Host '[3/5] VERIFY' -ForegroundColor Cyan

    foreach ($name in $targetNames) {
        $remaining = @(Get-NetFirewallRule -PolicyStore PersistentStore -Name ([string]$name) -ErrorAction SilentlyContinue)
        if ($remaining.Count -ne 0) {
            throw "FINAL VERIFY FAILED: target rule still exists: $name"
        }
    }

    Write-Host '  ALL TARGET RULES ABSENT : GREEN' -ForegroundColor Green

    Write-Host ''
    Write-Host '[4/5] COMMIT / ROLLBACK' -ForegroundColor Cyan
    $commitGreen = $true
    Write-Host '  COMMIT_GREEN' -ForegroundColor Green
}
catch {
    $failure = $_.Exception.Message

    Write-Host ''
    Write-Host 'EXECUTION FAILURE — STARTING ROLLBACK' -ForegroundColor Red
    Write-Host "Reason: $failure" -ForegroundColor Red

    $rollbackAttempted = $true
    $rollbackErrors = [System.Collections.Generic.List[string]]::new()

    # Roll back only rules that were successfully removed.
    foreach ($entry in @($removed)) {
        try {
            Restore-FirewallRuleFromSnapshot -Snapshot $entry.snapshot

            $restored = @(Get-NetFirewallRule -PolicyStore PersistentStore -Name ([string]$entry.name) -ErrorAction SilentlyContinue)
            if ($restored.Count -ne 1) {
                throw "Rollback verification failed: $($entry.name)"
            }

            $restoredSnapshot = Get-RuleSnapshot -Rule $restored[0]
            $restoredFp = Get-RuleFingerprint -Snapshot $restoredSnapshot

            $idx = [Array]::IndexOf($targetNames, [string]$entry.name)
            if ($idx -lt 0) {
                throw "Rollback fingerprint index missing: $($entry.name)"
            }

            if ($restoredFp -ne [string]$expectedFingerprints[$idx]) {
                throw "Rollback fingerprint mismatch: $($entry.name)"
            }

            Write-Host "  RESTORED + VERIFIED : $($entry.name)" -ForegroundColor Green
        }
        catch {
            $rollbackErrors.Add($_.Exception.Message)
            Write-Host "  ROLLBACK ERROR : $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    $rollbackGreen = ($rollbackErrors.Count -eq 0)

    [ordered]@{
        schema = 'vertex.transaction.rollback-receipt.v1'
        execution_id = $executionId
        transaction_id = [string]$manifest.transaction_id
        candidate_id = $CandidateId
        generated_at = (Get-Date).ToString('o')
        rollback_attempted = $rollbackAttempted
        rollback_green = $rollbackGreen
        restored_count = $removed.Count
        errors = @($rollbackErrors)
    } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $rollbackReceiptPath -Encoding UTF8
}
finally {
    Write-Host ''
    Write-Host '[5/5] RECEIPT' -ForegroundColor Cyan

    $status = if ($commitGreen) {
        'COMMIT_GREEN'
    }
    elseif ($rollbackAttempted -and $rollbackGreen) {
        'EXECUTION_FAILED_ROLLBACK_GREEN'
    }
    elseif ($rollbackAttempted) {
        'EXECUTION_FAILED_ROLLBACK_RED'
    }
    else {
        'EXECUTION_FAILED_NO_MUTATION_OR_UNKNOWN'
    }

    [ordered]@{
        schema = 'vertex.transaction.execution-receipt.v1'
        execution_id = $executionId
        transaction_id = [string]$manifest.transaction_id
        candidate_id = $CandidateId
        display_name = [string]$item.display_name
        generated_at = (Get-Date).ToString('o')
        mode = $Mode
        status = $status
        target_rules = $targetNames
        removed_count = $removed.Count
        commit_green = $commitGreen
        rollback_attempted = $rollbackAttempted
        rollback_green = $rollbackGreen
        failure = $failure
        old_program = $oldProgram
        replacement_program = $newProgram
        policy = [ordered]@{
            exact_fingerprint_required = $true
            verify_after_each_operation = $true
            rollback_on_failure = $true
            one_candidate_per_execution = $true
        }
    } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $receiptPath -Encoding UTF8

    Write-Host "  Status  : $status"
    Write-Host "  Receipt : $receiptPath"

    if (Test-Path -LiteralPath $rollbackReceiptPath) {
        Write-Host "  Rollback: $rollbackReceiptPath"
    }
}

if ($commitGreen) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' V2.6 TRANSACTION EXECUTION : COMMIT_GREEN' -ForegroundColor Green
    Write-Host " Candidate : $CandidateId"
    Write-Host " Rules     : $($targetNames.Count)"
    Write-Host '============================================================' -ForegroundColor Green
    exit 0
}

if ($rollbackAttempted -and $rollbackGreen) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Yellow
    Write-Host ' EXECUTION FAILED / ROLLBACK_GREEN' -ForegroundColor Yellow
    Write-Host ' ORIGINAL STATE RESTORED' -ForegroundColor Yellow
    Write-Host '============================================================' -ForegroundColor Yellow
    exit 2
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Red
Write-Host ' TRANSACTION FAILURE / ROLLBACK NOT VERIFIED' -ForegroundColor Red
Write-Host ' MANUAL REVIEW REQUIRED' -ForegroundColor Red
Write-Host '============================================================' -ForegroundColor Red
exit 3
