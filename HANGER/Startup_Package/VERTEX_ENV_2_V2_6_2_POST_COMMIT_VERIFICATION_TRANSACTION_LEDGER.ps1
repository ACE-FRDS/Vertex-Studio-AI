#requires -Version 7.0
<#
VERTEX ENV-2 V2.6.2 — POST-COMMIT VERIFICATION & TRANSACTION LEDGER
READ ONLY AGAINST SYSTEM STATE / LEDGER WRITE ONLY

PURPOSE
  Independently verify a previously COMMIT_GREEN V2.6/V2.6.1 execution.

FLOW
  FIND EXECUTION RECEIPT
    -> VERIFY RECEIPT
    -> VERIFY TARGET FIREWALL RULES ABSENT
    -> VERIFY OLD EXECUTABLE STILL ABSENT
    -> VERIFY REPLACEMENT EXECUTABLE PRESENT
    -> REGISTER TRANSACTION LEDGER ENTRY

SYSTEM SAFETY
  Firewall mutation : NONE
  Service mutation  : NONE
  Registry mutation : NONE
  File deletion     : NONE

ALLOWED WRITE
  Transaction ledger / verification reports under _vertex_reports only.
#>

[CmdletBinding()]
param(
    [string]$ExecutionId = '',
    [string]$CandidateId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$TxnRoot = Join-Path $ReportRoot '_transactions'
$LedgerRoot = Join-Path $ReportRoot '_transaction_ledger'
$LedgerPath = Join-Path $LedgerRoot 'VERTEX_TRANSACTION_LEDGER.json'

if (-not (Test-Path -LiteralPath $LedgerRoot)) {
    New-Item -ItemType Directory -Path $LedgerRoot -Force | Out-Null
}

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

function Get-ExecutionReceipts {
    if (-not (Test-Path -LiteralPath $TxnRoot)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $TxnRoot -Filter 'execution_receipt.json' -File -Recurse -ErrorAction SilentlyContinue
    )
}

function Get-Ledger {
    if (-not (Test-Path -LiteralPath $LedgerPath)) {
        return [ordered]@{
            schema = 'vertex.transaction.ledger.v1'
            created_at = (Get-Date).ToString('o')
            updated_at = (Get-Date).ToString('o')
            records = @()
        }
    }

    try {
        $data = Get-Content -LiteralPath $LedgerPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80
        return $data
    }
    catch {
        throw "Transaction ledger is unreadable: $LedgerPath"
    }
}

function Save-Ledger {
    param([Parameter(Mandatory)]$Ledger)

    if (-not ($Ledger.PSObject.Properties.Name -contains 'updated_at')) {
        $Ledger | Add-Member -NotePropertyName updated_at -NotePropertyValue (Get-Date).ToString('o')
    }
    else {
        $Ledger.updated_at = (Get-Date).ToString('o')
    }

    $Ledger | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $LedgerPath -Encoding UTF8
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.6.2 — POST-COMMIT VERIFICATION' -ForegroundColor Magenta
Write-Host ' RECEIPT -> LIVE VERIFY -> TRANSACTION LEDGER' -ForegroundColor Magenta
Write-Host ' SYSTEM STATE READ ONLY / LEDGER WRITE ONLY' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$receipts = Get-ExecutionReceipts

if ($ExecutionId) {
    $receipts = @(
        $receipts |
        Where-Object {
            try {
                $r = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 60
                [string](Get-SafeProperty -Object $r -Name 'execution_id' -Default '') -eq $ExecutionId
            }
            catch { $false }
        }
    )
}
elseif ($CandidateId) {
    $receipts = @(
        $receipts |
        Where-Object {
            try {
                $r = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 60
                [string](Get-SafeProperty -Object $r -Name 'candidate_id' -Default '') -eq $CandidateId
            }
            catch { $false }
        } |
        Sort-Object LastWriteTime -Descending
    )
}
else {
    $receipts = @($receipts | Sort-Object LastWriteTime -Descending)
}

if ($receipts.Count -eq 0) {
    throw 'No matching execution receipt found.'
}

$receiptFile = $receipts[0]
$receipt = Get-Content -LiteralPath $receiptFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 60

$executionIdValue = [string](Get-SafeProperty -Object $receipt -Name 'execution_id' -Default '')
$transactionId = [string](Get-SafeProperty -Object $receipt -Name 'transaction_id' -Default '')
$candidateIdValue = [string](Get-SafeProperty -Object $receipt -Name 'candidate_id' -Default '')
$displayName = [string](Get-SafeProperty -Object $receipt -Name 'display_name' -Default '')
$status = [string](Get-SafeProperty -Object $receipt -Name 'status' -Default '')
$targetRules = @(Get-SafeProperty -Object $receipt -Name 'target_rules' -Default @())
$oldProgram = [string](Get-SafeProperty -Object $receipt -Name 'old_program' -Default '')
$replacementProgram = [string](Get-SafeProperty -Object $receipt -Name 'replacement_program' -Default '')

Write-Host "Receipt       : $($receiptFile.FullName)"
Write-Host "Execution ID  : $executionIdValue"
Write-Host "Transaction   : $transactionId"
Write-Host "Candidate     : $candidateIdValue"
Write-Host "Display       : $displayName"
Write-Host "Status        : $status"

$findings = [System.Collections.Generic.List[object]]::new()
$green = $true

Write-Host ''
Write-Host '[1/4] RECEIPT VERIFY' -ForegroundColor Cyan

if ($status -ne 'COMMIT_GREEN') {
    $green = $false
    $findings.Add([pscustomobject]@{
        check='RECEIPT_STATUS'
        result='RED'
        detail="Expected COMMIT_GREEN, found $status"
    })
    Write-Host "  RED : Receipt status is $status" -ForegroundColor Red
}
else {
    $findings.Add([pscustomobject]@{
        check='RECEIPT_STATUS'
        result='GREEN'
        detail='COMMIT_GREEN'
    })
    Write-Host '  GREEN : COMMIT_GREEN'
}

if ([string]::IsNullOrWhiteSpace($executionIdValue) -or
    [string]::IsNullOrWhiteSpace($transactionId) -or
    [string]::IsNullOrWhiteSpace($candidateIdValue)) {
    $green = $false
    $findings.Add([pscustomobject]@{
        check='RECEIPT_IDENTITY'
        result='RED'
        detail='Missing execution/transaction/candidate identity.'
    })
    Write-Host '  RED : Receipt identity incomplete' -ForegroundColor Red
}
else {
    $findings.Add([pscustomobject]@{
        check='RECEIPT_IDENTITY'
        result='GREEN'
        detail='Identity fields present.'
    })
    Write-Host '  GREEN : Receipt identity complete'
}

Write-Host ''
Write-Host '[2/4] FIREWALL POST-COMMIT VERIFY' -ForegroundColor Cyan

foreach ($ruleName in $targetRules) {
    $stillThere = @(
        Get-NetFirewallRule -PolicyStore PersistentStore -Name ([string]$ruleName) -ErrorAction SilentlyContinue
    )

    if ($stillThere.Count -eq 0) {
        $findings.Add([pscustomobject]@{
            check='TARGET_RULE_ABSENT'
            target=[string]$ruleName
            result='GREEN'
            detail='Rule remains absent after commit.'
        })
        Write-Host "  GREEN : ABSENT : $ruleName"
    }
    else {
        $green = $false
        $findings.Add([pscustomobject]@{
            check='TARGET_RULE_ABSENT'
            target=[string]$ruleName
            result='RED'
            detail="Rule exists again. Count=$($stillThere.Count)"
        })
        Write-Host "  RED : RULE RETURNED : $ruleName" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '[3/4] APPLICATION STATE VERIFY' -ForegroundColor Cyan

$oldExists = $false
if ($oldProgram) {
    $oldExists = Test-Path -LiteralPath $oldProgram.Trim().Trim('"') -PathType Leaf -ErrorAction SilentlyContinue
}

$newExists = $false
if ($replacementProgram) {
    $newExists = Test-Path -LiteralPath $replacementProgram.Trim().Trim('"') -PathType Leaf -ErrorAction SilentlyContinue
}

if ($oldExists) {
    $green = $false
    $findings.Add([pscustomobject]@{
        check='OLD_EXECUTABLE_ABSENT'
        result='RED'
        detail="Old executable returned: $oldProgram"
    })
    Write-Host "  RED : OLD EXECUTABLE RETURNED : $oldProgram" -ForegroundColor Red
}
else {
    $findings.Add([pscustomobject]@{
        check='OLD_EXECUTABLE_ABSENT'
        result='GREEN'
        detail='Old executable remains absent.'
    })
    Write-Host '  GREEN : Old executable remains absent'
}

if (-not $newExists) {
    $green = $false
    $findings.Add([pscustomobject]@{
        check='REPLACEMENT_EXECUTABLE_PRESENT'
        result='RED'
        detail="Replacement executable missing: $replacementProgram"
    })
    Write-Host "  RED : REPLACEMENT MISSING : $replacementProgram" -ForegroundColor Red
}
else {
    $findings.Add([pscustomobject]@{
        check='REPLACEMENT_EXECUTABLE_PRESENT'
        result='GREEN'
        detail='Replacement executable remains present.'
    })
    Write-Host '  GREEN : Replacement executable remains present'
}

Write-Host ''
Write-Host '[4/4] TRANSACTION LEDGER' -ForegroundColor Cyan

$verificationStatus = if ($green) {
    'POST_COMMIT_GREEN'
}
else {
    'POST_COMMIT_RED'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportJson = Join-Path $ReportRoot "VERTEX_POST_COMMIT_VERIFICATION.$stamp.json"
$reportTxt = Join-Path $ReportRoot "VERTEX_POST_COMMIT_VERIFICATION.$stamp.txt"

$verificationReport = [ordered]@{
    schema = 'vertex.transaction.post-commit-verification.v1'
    generated_at = (Get-Date).ToString('o')
    execution_id = $executionIdValue
    transaction_id = $transactionId
    candidate_id = $candidateIdValue
    display_name = $displayName
    source_receipt = $receiptFile.FullName
    original_status = $status
    verification_status = $verificationStatus
    target_rules = $targetRules
    old_program = $oldProgram
    replacement_program = $replacementProgram
    findings = @($findings)
    system_mutation = 'NONE'
    ledger_write = 'ALLOWED'
}

$verificationReport | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $reportJson -Encoding UTF8

$ledger = Get-Ledger
$records = @(
    Get-SafeProperty -Object $ledger -Name 'records' -Default @()
)

$existing = @(
    $records |
    Where-Object {
        [string](Get-SafeProperty -Object $_ -Name 'execution_id' -Default '') -eq $executionIdValue
    }
)

$ledgerAction = ''

if ($existing.Count -eq 0) {
    $records += [pscustomobject][ordered]@{
        execution_id = $executionIdValue
        transaction_id = $transactionId
        candidate_id = $candidateIdValue
        display_name = $displayName
        committed_at = [string](Get-SafeProperty -Object $receipt -Name 'generated_at' -Default '')
        post_commit_verified_at = (Get-Date).ToString('o')
        status = $verificationStatus
        target_rules = $targetRules
        old_program = $oldProgram
        replacement_program = $replacementProgram
        receipt_path = $receiptFile.FullName
        verification_report = $reportJson
        lifecycle_state = if ($green) { 'COMMITTED_VERIFIED' } else { 'COMMITTED_REVIEW_REQUIRED' }
    }

    $ledger.records = $records
    Save-Ledger -Ledger $ledger
    $ledgerAction = 'REGISTERED'
}
else {
    # Update verification state without creating duplicates.
    foreach ($record in $records) {
        if ([string](Get-SafeProperty -Object $record -Name 'execution_id' -Default '') -eq $executionIdValue) {
            if (-not ($record.PSObject.Properties.Name -contains 'post_commit_verified_at')) {
                $record | Add-Member -NotePropertyName post_commit_verified_at -NotePropertyValue (Get-Date).ToString('o')
            } else {
                $record.post_commit_verified_at = (Get-Date).ToString('o')
            }

            if (-not ($record.PSObject.Properties.Name -contains 'status')) {
                $record | Add-Member -NotePropertyName status -NotePropertyValue $verificationStatus
            } else {
                $record.status = $verificationStatus
            }

            if (-not ($record.PSObject.Properties.Name -contains 'verification_report')) {
                $record | Add-Member -NotePropertyName verification_report -NotePropertyValue $reportJson
            } else {
                $record.verification_report = $reportJson
            }

            $lifecycle = if ($green) { 'COMMITTED_VERIFIED' } else { 'COMMITTED_REVIEW_REQUIRED' }

            if (-not ($record.PSObject.Properties.Name -contains 'lifecycle_state')) {
                $record | Add-Member -NotePropertyName lifecycle_state -NotePropertyValue $lifecycle
            } else {
                $record.lifecycle_state = $lifecycle
            }
        }
    }

    $ledger.records = $records
    Save-Ledger -Ledger $ledger
    $ledgerAction = 'UPDATED'
}

Write-Host "  Ledger action : $ledgerAction"
Write-Host "  Ledger        : $LedgerPath"

@(
    '============================================================',
    ' VERTEX ENV-2 V2.6.2 — POST-COMMIT VERIFICATION',
    '============================================================',
    " Execution ID        : $executionIdValue",
    " Transaction ID      : $transactionId",
    " Candidate           : $candidateIdValue",
    " Display             : $displayName",
    " Verification        : $verificationStatus",
    " Ledger Action       : $ledgerAction",
    '',
    " Target Rules        : $($targetRules.Count)",
    " Old EXE Absent      : $(-not $oldExists)",
    " Replacement Present : $newExists",
    '',
    ' Firewall Mutation   : NONE',
    ' System Mutation     : NONE',
    ' Ledger Write        : ALLOWED',
    '',
    " JSON                : $reportJson",
    " TXT                 : $reportTxt",
    " Ledger              : $LedgerPath",
    '============================================================'
) | Set-Content -LiteralPath $reportTxt -Encoding UTF8

Write-Host ''
Write-Host '============================================================'

if ($green) {
    Write-Host ' POST-COMMIT VERIFICATION : GREEN' -ForegroundColor Green
    Write-Host ' TRANSACTION LIFECYCLE     : COMMITTED_VERIFIED' -ForegroundColor Green
}
else {
    Write-Host ' POST-COMMIT VERIFICATION : RED' -ForegroundColor Red
    Write-Host ' TRANSACTION LIFECYCLE     : COMMITTED_REVIEW_REQUIRED' -ForegroundColor Red
}

Write-Host " Execution ID              : $executionIdValue"
Write-Host " Candidate                 : $candidateIdValue"
Write-Host " Ledger                    : $LedgerPath"
Write-Host " Report                    : $reportJson"
Write-Host '============================================================'

if (-not $green) {
    exit 2
}
