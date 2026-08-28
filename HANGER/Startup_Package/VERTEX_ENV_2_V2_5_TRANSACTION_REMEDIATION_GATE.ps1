#requires -Version 7.0
<#
VERTEX ENV-2 V2.5 — TRANSACTION REMEDIATION GATE
READ ONLY / ZERO MUTATION

PURPOSE
  Convert V2.4.13 REMEDIATION_ELIGIBLE findings into transaction-grade
  firewall remediation packages.

FLOW
  DISCOVER ELIGIBLE
    -> RESOLVE EXACT LIVE RULES
    -> REVALIDATE CURRENT STATE
    -> SNAPSHOT FULL RULE EVIDENCE
    -> BUILD TRANSACTION MANIFEST
    -> HUMAN GATE

IMPORTANT
  This script DOES NOT delete or modify firewall rules.
  It prepares evidence required by a later transaction executor.

VERTEX TRANSACTION PRINCIPLE
  "Do not touch state until the return path exists."
#>

[CmdletBinding()]
param(
    [ValidateSet('Audit','Prepare')]
    [string]$Mode = 'Audit',

    [string]$CandidateId = '',

    [string]$Approval = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$TxnRoot = Join-Path $ReportRoot '_transactions'

if (-not (Test-Path -LiteralPath $TxnRoot)) {
    New-Item -ItemType Directory -Path $TxnRoot -Force | Out-Null
}

function Get-SafeProperty {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    if ($null -eq $prop.Value) { return $Default }

    return $prop.Value
}

function Normalize-ProgramPath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }

    return $Path.Trim().Trim('"').Replace('/','\').ToLowerInvariant()
}

function Get-RuleSnapshot {
    param(
        [Parameter(Mandatory)]$Rule
    )

    $app = $Rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
    $port = $Rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
    $addr = $Rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
    $svc  = $Rule | Get-NetFirewallServiceFilter -ErrorAction SilentlyContinue
    $sec  = $Rule | Get-NetFirewallSecurityFilter -ErrorAction SilentlyContinue
    $iface = $Rule | Get-NetFirewallInterfaceFilter -ErrorAction SilentlyContinue

    return [pscustomobject][ordered]@{
        name                       = [string]$Rule.Name
        display_name               = [string]$Rule.DisplayName
        description                = [string]$Rule.Description
        group                      = [string]$Rule.Group
        display_group              = [string]$Rule.DisplayGroup
        enabled                    = [string]$Rule.Enabled
        profile                    = [string]$Rule.Profile
        direction                  = [string]$Rule.Direction
        action                     = [string]$Rule.Action
        edge_traversal_policy      = [string]$Rule.EdgeTraversalPolicy
        loose_source_mapping       = [string]$Rule.LooseSourceMapping
        local_only_mapping         = [string]$Rule.LocalOnlyMapping
        owner                      = [string]$Rule.Owner
        primary_status             = [string]$Rule.PrimaryStatus
        status                     = [string]$Rule.Status
        enforcement_status         = @($Rule.EnforcementStatus | ForEach-Object { [string]$_ })
        policy_store_source        = [string]$Rule.PolicyStoreSource
        policy_store_source_type   = [string]$Rule.PolicyStoreSourceType

        application = [ordered]@{
            program = [string](Get-SafeProperty -Object $app -Name 'Program' -Default '')
            package = [string](Get-SafeProperty -Object $app -Name 'Package' -Default '')
        }

        port = [ordered]@{
            protocol   = [string](Get-SafeProperty -Object $port -Name 'Protocol' -Default '')
            local_port = [string](Get-SafeProperty -Object $port -Name 'LocalPort' -Default '')
            remote_port = [string](Get-SafeProperty -Object $port -Name 'RemotePort' -Default '')
            icmp_type  = [string](Get-SafeProperty -Object $port -Name 'IcmpType' -Default '')
        }

        address = [ordered]@{
            local_address  = [string](Get-SafeProperty -Object $addr -Name 'LocalAddress' -Default '')
            remote_address = [string](Get-SafeProperty -Object $addr -Name 'RemoteAddress' -Default '')
        }

        service = [ordered]@{
            service = [string](Get-SafeProperty -Object $svc -Name 'Service' -Default '')
        }

        security = [ordered]@{
            authentication = [string](Get-SafeProperty -Object $sec -Name 'Authentication' -Default '')
            encryption     = [string](Get-SafeProperty -Object $sec -Name 'Encryption' -Default '')
            local_user     = [string](Get-SafeProperty -Object $sec -Name 'LocalUser' -Default '')
            remote_user    = [string](Get-SafeProperty -Object $sec -Name 'RemoteUser' -Default '')
            remote_machine = [string](Get-SafeProperty -Object $sec -Name 'RemoteMachine' -Default '')
        }

        interface = [ordered]@{
            interface_alias = @(
                Get-SafeProperty -Object $iface -Name 'InterfaceAlias' -Default @()
            )
        }
    }
}

function Get-RuleFingerprint {
    param(
        [Parameter(Mandatory)]$Snapshot
    )

    $canonical = [ordered]@{
        name       = $Snapshot.name
        enabled    = $Snapshot.enabled
        profile    = $Snapshot.profile
        direction  = $Snapshot.direction
        action     = $Snapshot.action
        program    = $Snapshot.application.program
        protocol   = $Snapshot.port.protocol
        local_port = $Snapshot.port.local_port
        remote_port = $Snapshot.port.remote_port
        local_addr = $Snapshot.address.local_address
        remote_addr = $Snapshot.address.remote_address
        service    = $Snapshot.service.service
        source     = $Snapshot.policy_store_source
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

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.5 — TRANSACTION REMEDIATION GATE' -ForegroundColor Magenta
Write-Host ' ELIGIBLE -> LIVE VERIFY -> SNAPSHOT -> TRANSACTION MANIFEST' -ForegroundColor Magenta
Write-Host ' READ ONLY / ZERO FIREWALL MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$source = Get-ChildItem -LiteralPath $ReportRoot -Filter 'VERTEX_PRODUCT_LINEAGE_BOUNDARY.*.json' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $source) {
    throw 'No V2.4.13 product-lineage report found.'
}

$data = Get-Content -LiteralPath $source.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 60

$eligible = @(
    $data.candidates |
    Where-Object {
        [string](Get-SafeProperty -Object $_ -Name 'boundary_decision' -Default '') -eq 'REMEDIATION_ELIGIBLE'
    }
)

if ($CandidateId) {
    $eligible = @(
        $eligible |
        Where-Object {
            [string](Get-SafeProperty -Object $_ -Name 'candidate_id' -Default '') -eq $CandidateId
        }
    )
}

Write-Host "Source                : $($source.FullName)"
Write-Host "Eligible candidates   : $($eligible.Count)"

if ($eligible.Count -eq 0) {
    throw 'No remediation-eligible candidates matched.'
}

if ($Mode -eq 'Prepare' -and $Approval -ne 'APPROVE-TXN-PREPARE') {
    throw 'Prepare mode requires -Approval "APPROVE-TXN-PREPARE".'
}

$liveRules = @(
    Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop
)

$results = [System.Collections.Generic.List[object]]::new()
$transactionItems = [System.Collections.Generic.List[object]]::new()

$index = 0

foreach ($candidate in $eligible) {
    $index++

    $candidateId = [string](Get-SafeProperty -Object $candidate -Name 'candidate_id' -Default '')
    $displayName = [string](Get-SafeProperty -Object $candidate -Name 'display_name' -Default '')
    $oldProgram = [string](Get-SafeProperty -Object $candidate -Name 'old_program' -Default '')
    $newProgram = [string](Get-SafeProperty -Object $candidate -Name 'new_program' -Default '')
    $ruleNames = @(
        Get-SafeProperty -Object $candidate -Name 'firewall_rule_names' -Default @()
    )

    $resolvedRules = [System.Collections.Generic.List[object]]::new()
    $resolveMethod = 'NONE'

    # Strongest evidence: exact rule identities carried forward.
    if ($ruleNames.Count -gt 0) {
        foreach ($ruleName in $ruleNames) {
            $match = @(
                $liveRules |
                Where-Object { [string]$_.Name -eq [string]$ruleName }
            )

            foreach ($r in $match) {
                $resolvedRules.Add($r)
            }
        }

        if ($resolvedRules.Count -gt 0) {
            $resolveMethod = 'EXACT_RULE_ID'
        }
    }

    # Stage-handoff recovery: if exact rule IDs were not preserved,
    # resolve only rules whose application path exactly matches old_program.
    if ($resolvedRules.Count -eq 0 -and $oldProgram) {
        foreach ($rule in $liveRules) {
            $app = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
            $program = [string](Get-SafeProperty -Object $app -Name 'Program' -Default '')

            if (
                (Normalize-ProgramPath $program) -eq (Normalize-ProgramPath $oldProgram)
            ) {
                $resolvedRules.Add($rule)
            }
        }

        if ($resolvedRules.Count -gt 0) {
            $resolveMethod = 'EXACT_OLD_PROGRAM_PATH'
        }
    }

    $snapshots = @()
    $fingerprints = @()
    $liveEligible = $true
    $guards = [System.Collections.Generic.List[string]]::new()

    if ($resolvedRules.Count -eq 0) {
        $liveEligible = $false
        $guards.Add('No exact live firewall rule could be resolved.')
    }
    else {
        foreach ($rule in @($resolvedRules)) {
            $snap = Get-RuleSnapshot -Rule $rule
            $fp = Get-RuleFingerprint -Snapshot $snap

            $snapshots += $snap
            $fingerprints += $fp

            $liveProgram = Normalize-ProgramPath $snap.application.program
            $expectedOld = Normalize-ProgramPath $oldProgram

            if ($expectedOld -and $liveProgram -ne $expectedOld) {
                $liveEligible = $false
                $guards.Add("Program drift detected for rule $($snap.name).")
            }

            # This transaction class is only for stale application-bound rules.
            if (-not $snap.application.program -or $snap.application.program -eq 'Any') {
                $liveEligible = $false
                $guards.Add("Rule $($snap.name) is not application-bound.")
            }
        }
    }

    $oldExistsNow = $false
    if ($oldProgram) {
        $oldExistsNow = Test-Path -LiteralPath $oldProgram.Trim().Trim('"') -PathType Leaf -ErrorAction SilentlyContinue
    }

    if ($oldExistsNow) {
        $liveEligible = $false
        $guards.Add('Old executable has returned; stale assumption invalidated.')
    }

    $newExistsNow = $false
    if ($newProgram) {
        $newExistsNow = Test-Path -LiteralPath $newProgram.Trim().Trim('"') -PathType Leaf -ErrorAction SilentlyContinue
    }

    if (-not $newExistsNow) {
        $liveEligible = $false
        $guards.Add('Replacement executable no longer exists.')
    }

    $status = if ($liveEligible) {
        'TRANSACTION_PREP_ELIGIBLE'
    }
    else {
        'TRANSACTION_PREP_DENIED'
    }

    $result = [pscustomobject][ordered]@{
        candidate_id           = $candidateId
        display_name           = $displayName
        old_program            = $oldProgram
        new_program            = $newProgram
        resolve_method         = $resolveMethod
        resolved_rule_count    = $resolvedRules.Count
        old_program_exists_now = $oldExistsNow
        new_program_exists_now = $newExistsNow
        live_revalidation      = $status
        firewall_snapshots     = $snapshots
        fingerprints           = $fingerprints
        guards                 = @($guards)
        mutation               = 'NONE'
    }

    $results.Add($result)

    if ($liveEligible) {
        $transactionItems.Add([pscustomobject][ordered]@{
            candidate_id = $candidateId
            display_name = $displayName
            operation = 'REMOVE_STALE_FIREWALL_RULES'
            target_rule_names = @($snapshots | ForEach-Object { $_.name })
            expected_fingerprints = $fingerprints
            old_program = $oldProgram
            replacement_program = $newProgram
            rollback_snapshot = $snapshots
            preconditions = @(
                'Exact live rule identity/fingerprint must still match.',
                'Old executable must remain absent.',
                'Replacement executable must remain present.',
                'Human approval is required.',
                'Rollback reconstruction data must be available.'
            )
        })
    }

    $color = if ($liveEligible) { 'Green' } else { 'Yellow' }

    Write-Host ''
    Write-Host "[$status] $candidateId $displayName" -ForegroundColor $color
    Write-Host "  Resolve       : $resolveMethod"
    Write-Host "  Rules         : $($resolvedRules.Count)"
    Write-Host "  Old exists    : $oldExistsNow"
    Write-Host "  New exists    : $newExistsNow"

    if ($guards.Count -gt 0) {
        Write-Host "  Guard         : $($guards -join ' | ')"
    }
}

$txnId = 'VTXN-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$txnDir = Join-Path $TxnRoot $txnId

if ($Mode -eq 'Prepare') {
    New-Item -ItemType Directory -Path $txnDir -Force | Out-Null
}

$counts = [ordered]@{
    input_eligible             = $eligible.Count
    transaction_prep_eligible = @($results | Where-Object live_revalidation -eq 'TRANSACTION_PREP_ELIGIBLE').Count
    transaction_prep_denied   = @($results | Where-Object live_revalidation -eq 'TRANSACTION_PREP_DENIED').Count
    transaction_items         = $transactionItems.Count
}

$manifest = [ordered]@{
    schema = 'vertex.transaction.firewall-remediation.v1'
    transaction_id = $txnId
    mission = 'VERTEX_ENV_2_V2_5_TRANSACTION_REMEDIATION_GATE'
    generated_at = (Get-Date).ToString('o')
    mode = $Mode
    source_report = $source.FullName

    counts = $counts
    audit_results = @($results)
    transaction_items = @($transactionItems)

    transaction_policy = [ordered]@{
        state = 'PREPARED_NOT_EXECUTED'
        filesystem_mutation = 'REPORT_FILES_ONLY'
        firewall_mutation = 'DENIED'
        automatic_commit = 'DENIED'
        automatic_delete = 'DENIED'
        human_gate = 'REQUIRED'
        live_revalidation_before_execute = 'REQUIRED'
        exact_fingerprint_match = 'REQUIRED'
        rollback_before_touch = 'REQUIRED'
        verify_after_each_operation = 'REQUIRED'
        rollback_on_failure = 'REQUIRED'
        commit_only_if_all_green = 'REQUIRED'
        principle = 'Do not touch state until the return path exists.'
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportJson = Join-Path $ReportRoot "VERTEX_TRANSACTION_GATE.$stamp.json"
$reportTxt  = Join-Path $ReportRoot "VERTEX_TRANSACTION_GATE.$stamp.txt"

$manifest | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $reportJson -Encoding UTF8

if ($Mode -eq 'Prepare') {
    $manifestPath = Join-Path $txnDir 'transaction_manifest.json'
    $snapshotPath = Join-Path $txnDir 'rollback_snapshot.json'
    $readmePath   = Join-Path $txnDir 'TRANSACTION_STATUS.txt'

    $manifest | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    [ordered]@{
        transaction_id = $txnId
        generated_at = (Get-Date).ToString('o')
        source = $source.FullName
        snapshots = @(
            $transactionItems |
            ForEach-Object {
                [ordered]@{
                    candidate_id = $_.candidate_id
                    display_name = $_.display_name
                    rules = $_.rollback_snapshot
                }
            }
        )
    } | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $snapshotPath -Encoding UTF8

    @(
        'VERTEX TRANSACTION PACKAGE',
        "Transaction ID : $txnId",
        'State          : PREPARED_NOT_EXECUTED',
        'Firewall       : UNCHANGED',
        'Human Gate     : REQUIRED',
        '',
        'This package contains:',
        ' - Exact live firewall evidence',
        ' - SHA-256 transaction fingerprints',
        ' - Rollback reconstruction snapshot',
        ' - Transaction preconditions',
        '',
        'No remediation has been executed.'
    ) | Set-Content -LiteralPath $readmePath -Encoding UTF8
}

@(
    '============================================================',
    ' VERTEX ENV-2 V2.5 — TRANSACTION REMEDIATION GATE',
    '============================================================',
    " Mode                         : $Mode",
    " Transaction ID               : $txnId",
    " Source                       : $($source.FullName)",
    " Input eligible               : $($counts.input_eligible)",
    " Transaction prep eligible    : $($counts.transaction_prep_eligible)",
    " Transaction prep denied      : $($counts.transaction_prep_denied)",
    " Transaction items            : $($counts.transaction_items)",
    '',
    ' Firewall mutation            : DENIED',
    ' Human gate                   : REQUIRED',
    ' Rollback-before-touch        : REQUIRED',
    ' Commit only if all green     : REQUIRED',
    '',
    " JSON                         : $reportJson",
    " TXT                          : $reportTxt",
    $(if ($Mode -eq 'Prepare') { " Transaction package          : $txnDir" } else { ' Transaction package          : NOT WRITTEN IN AUDIT MODE' }),
    '============================================================'
) | Set-Content -LiteralPath $reportTxt -Encoding UTF8

Write-Host ''
Write-Host '============================================================'
Write-Host ' VERTEX TRANSACTION GATE SUMMARY'
Write-Host '============================================================'
Write-Host " Mode                      : $Mode"
Write-Host " Transaction ID            : $txnId"
Write-Host " Input eligible            : $($counts.input_eligible)"
Write-Host " Transaction prep eligible : $($counts.transaction_prep_eligible)" -ForegroundColor Green
Write-Host " Transaction prep denied   : $($counts.transaction_prep_denied)" -ForegroundColor Yellow
Write-Host " Transaction items         : $($counts.transaction_items)"
Write-Host ''
Write-Host ' FIREWALL MUTATION         : DENIED'
Write-Host ' HUMAN GATE               : REQUIRED'
Write-Host ' ROLLBACK BEFORE TOUCH     : REQUIRED'
Write-Host ' COMMIT ONLY IF ALL GREEN  : REQUIRED'
Write-Host ''
Write-Host " JSON                      : $reportJson"
Write-Host " TXT                       : $reportTxt"

if ($Mode -eq 'Prepare') {
    Write-Host " Transaction Package       : $txnDir" -ForegroundColor Cyan
}

Write-Host '============================================================' -ForegroundColor Green
Write-Host ' V2.5 TRANSACTION GATE : GREEN' -ForegroundColor Green
Write-Host ' NO FIREWALL MUTATION PERFORMED' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green

if ($Mode -eq 'Audit') {
    Write-Host ''
    Write-Host 'NEXT'
    Write-Host ' If this audit is correct, prepare immutable transaction evidence with:'
    Write-Host ''
    Write-Host '  -Mode Prepare -Approval "APPROVE-TXN-PREPARE"'
}
