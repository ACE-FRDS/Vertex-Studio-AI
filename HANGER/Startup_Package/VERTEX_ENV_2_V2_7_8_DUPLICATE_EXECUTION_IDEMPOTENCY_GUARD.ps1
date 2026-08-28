#requires -Version 7.0
<#
VERTEX ENV-2 V2.7.8 — DUPLICATE EXECUTION / IDEMPOTENCY GUARD
READ ONLY AGAINST SYSTEM STATE / LEDGER AUDIT ONLY

PURPOSE
  Prevent duplicate execution of an already committed transaction/candidate
  before the Provider Invocation Gateway can call a mutating provider.

CHECKS
  - Transaction Ledger
  - Candidate identity
  - Transaction identity
  - Provider / resource / operation tuple
  - Prior COMMITTED_VERIFIED state
  - Prior gateway/provider receipts when available

RESULT
  ALLOW_FIRST_EXECUTION
  DENY_ALREADY_COMMITTED
  HOLD_IDENTITY_AMBIGUOUS

NO PROVIDER EXECUTION.
#>

[CmdletBinding()]
param(
    [string]$CandidateId = '',
    [string]$TransactionId = '',
    [string]$Provider = 'VertexFirewallProvider',
    [string]$ResourceType = 'WINDOWS_FIREWALL_RULE',
    [string]$Operation = 'EXECUTE'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$CoreRoot   = Join-Path $ReportRoot '_transaction_core'
$LedgerPath = Join-Path $ReportRoot '_transaction_ledger\VERTEX_TRANSACTION_LEDGER.json'

function Get-SafeProperty {
    param([AllowNull()]$Object,[Parameter(Mandatory)][string]$Name,$Default=$null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.7.8 — IDEMPOTENCY GUARD' -ForegroundColor Magenta
Write-Host ' LEDGER -> IDENTITY -> DUPLICATE EXECUTION DECISION' -ForegroundColor Magenta
Write-Host ' ZERO PROVIDER EXECUTION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

# If candidate omitted, resolve from latest completed dispatch/revalidation context.
if ([string]::IsNullOrWhiteSpace($CandidateId)) {
    $latestGateway = Get-ChildItem -LiteralPath $CoreRoot -Filter 'VERTEX_PROVIDER_INVOCATION_GATEWAY.*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($latestGateway) {
        $g = Get-Content -LiteralPath $latestGateway.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80
        $CandidateId = [string](Get-SafeProperty $g 'candidate_id' '')
        if ([string]::IsNullOrWhiteSpace($TransactionId)) {
            $TransactionId = [string](Get-SafeProperty $g 'transaction_id' '')
        }
    }
}

Write-Host ''
Write-Host '[1/4] REQUEST IDENTITY' -ForegroundColor Cyan
Write-Host "  Candidate   : $CandidateId"
Write-Host "  Transaction : $TransactionId"
Write-Host "  Provider    : $Provider"
Write-Host "  Resource    : $ResourceType"
Write-Host "  Operation   : $Operation"

$committedMatches = [System.Collections.Generic.List[object]]::new()
$ambiguousMatches = [System.Collections.Generic.List[object]]::new()

Write-Host ''
Write-Host '[2/4] TRANSACTION LEDGER AUDIT' -ForegroundColor Cyan

if (Test-Path -LiteralPath $LedgerPath -PathType Leaf) {
    $ledgerRaw = Get-Content -LiteralPath $LedgerPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100

    # Support either top-level array or object containing entries/transactions.
    $entries = @()
    if ($ledgerRaw -is [System.Array]) {
        $entries = @($ledgerRaw)
    }
    else {
        $entriesProp = Get-SafeProperty $ledgerRaw 'entries' $null
        $transactionsProp = Get-SafeProperty $ledgerRaw 'transactions' $null

        if ($null -ne $entriesProp) {
            $entries = @($entriesProp)
        }
        elseif ($null -ne $transactionsProp) {
            $entries = @($transactionsProp)
        }
        else {
            $entries = @($ledgerRaw)
        }
    }

    Write-Host "  Ledger      : $LedgerPath"
    Write-Host "  Entries     : $($entries.Count)"

    foreach ($entry in $entries) {
        $entryCandidate = [string](Get-SafeProperty $entry 'candidate_id' '')
        $entryTxn       = [string](Get-SafeProperty $entry 'transaction_id' '')
        $entryExecution = [string](Get-SafeProperty $entry 'execution_id' '')
        $entryStatus    = [string](Get-SafeProperty $entry 'status' '')
        $entryLifecycle = [string](Get-SafeProperty $entry 'transaction_lifecycle' '')
        if (-not $entryLifecycle) {
            $entryLifecycle = [string](Get-SafeProperty $entry 'lifecycle' '')
        }

        $candidateMatch = (-not [string]::IsNullOrWhiteSpace($CandidateId)) -and ($entryCandidate -eq $CandidateId)
        $txnMatch = (-not [string]::IsNullOrWhiteSpace($TransactionId)) -and ($entryTxn -eq $TransactionId)

        $committed = (
            $entryStatus -in @('COMMIT_GREEN','COMMITTED_VERIFIED') -or
            $entryLifecycle -in @('COMMIT_GREEN','COMMITTED_VERIFIED')
        )

        if (($candidateMatch -or $txnMatch) -and $committed) {
            $committedMatches.Add([pscustomobject]@{
                candidate_id = $entryCandidate
                transaction_id = $entryTxn
                execution_id = $entryExecution
                status = $entryStatus
                lifecycle = $entryLifecycle
                source = 'TRANSACTION_LEDGER'
            })
        }
        elseif ($candidateMatch -or $txnMatch) {
            $ambiguousMatches.Add([pscustomobject]@{
                candidate_id = $entryCandidate
                transaction_id = $entryTxn
                execution_id = $entryExecution
                status = $entryStatus
                lifecycle = $entryLifecycle
                source = 'TRANSACTION_LEDGER'
            })
        }
    }
}
else {
    Write-Host '  Ledger not found.' -ForegroundColor Yellow
}

# Also audit post-commit verification reports because they are authoritative
# evidence for the existing V2.6.2 lifecycle.
$postReports = @(Get-ChildItem -LiteralPath $ReportRoot -Filter 'VERTEX_POST_COMMIT_VERIFICATION.*.json' -File -ErrorAction SilentlyContinue)

foreach ($file in $postReports) {
    try {
        $r = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 80
        $rc = [string](Get-SafeProperty $r 'candidate_id' '')
        $rt = [string](Get-SafeProperty $r 'transaction_id' '')
        $re = [string](Get-SafeProperty $r 'execution_id' '')
        $rs = [string](Get-SafeProperty $r 'status' '')
        $rl = [string](Get-SafeProperty $r 'transaction_lifecycle' '')

        $candidateMatch = (-not [string]::IsNullOrWhiteSpace($CandidateId)) -and ($rc -eq $CandidateId)
        $txnMatch = (-not [string]::IsNullOrWhiteSpace($TransactionId)) -and ($rt -eq $TransactionId)

        if (($candidateMatch -or $txnMatch) -and ($rs -eq 'COMMITTED_VERIFIED' -or $rl -eq 'COMMITTED_VERIFIED')) {
            $committedMatches.Add([pscustomobject]@{
                candidate_id = $rc
                transaction_id = $rt
                execution_id = $re
                status = $rs
                lifecycle = $rl
                source = $file.FullName
            })
        }
    }
    catch {
        # A malformed historical report must not crash the guard.
        $ambiguousMatches.Add([pscustomobject]@{
            candidate_id = ''
            transaction_id = ''
            execution_id = ''
            status = 'UNREADABLE_REPORT'
            lifecycle = ''
            source = $file.FullName
        })
    }
}

Write-Host ''
Write-Host '[3/4] IDEMPOTENCY DECISION' -ForegroundColor Cyan

$decision = 'ALLOW_FIRST_EXECUTION'
$reason = 'No prior committed execution matched the supplied identity.'

if ([string]::IsNullOrWhiteSpace($CandidateId) -and [string]::IsNullOrWhiteSpace($TransactionId)) {
    $decision = 'HOLD_IDENTITY_AMBIGUOUS'
    $reason = 'Neither CandidateId nor TransactionId is available.'
}
elseif ($committedMatches.Count -gt 0) {
    $decision = 'DENY_ALREADY_COMMITTED'
    $reason = 'A prior committed/verified execution matches this identity.'
}
elseif ($ambiguousMatches.Count -gt 0) {
    $decision = 'HOLD_IDENTITY_AMBIGUOUS'
    $reason = 'Historical identity exists but terminal state is not sufficiently proven.'
}

$color = switch ($decision) {
    'ALLOW_FIRST_EXECUTION' { 'Green' }
    'HOLD_IDENTITY_AMBIGUOUS' { 'Yellow' }
    default { 'Red' }
}

Write-Host "  DECISION : $decision" -ForegroundColor $color
Write-Host "  Reason   : $reason"
Write-Host "  Committed Matches : $($committedMatches.Count)"
Write-Host "  Ambiguous Matches : $($ambiguousMatches.Count)"

foreach ($m in $committedMatches) {
    Write-Host "  COMMITTED : Candidate=$($m.candidate_id) Txn=$($m.transaction_id) Exec=$($m.execution_id) Status=$($m.status) Lifecycle=$($m.lifecycle)"
}

Write-Host ''
Write-Host '[4/4] GUARD RECEIPT' -ForegroundColor Cyan

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $CoreRoot "VERTEX_IDEMPOTENCY_GUARD.$stamp.json"
$txt  = Join-Path $CoreRoot "VERTEX_IDEMPOTENCY_GUARD.$stamp.txt"

$receipt = [ordered]@{
    schema = 'vertex.transaction.idempotency-guard.v1'
    version = '2.7.8'
    generated_at = (Get-Date).ToString('o')
    request = [ordered]@{
        candidate_id = $CandidateId
        transaction_id = $TransactionId
        provider = $Provider
        resource_type = $ResourceType
        operation = $Operation
    }
    decision = $decision
    reason = $reason
    committed_matches = @($committedMatches)
    ambiguous_matches = @($ambiguousMatches)
    safety = [ordered]@{
        provider_execution = 'NONE'
        system_mutation = 'NONE'
        ledger_read_only = $true
    }
}

$receipt | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX IDEMPOTENCY GUARD V2.7.8',
    '============================================================',
    " Candidate          : $CandidateId",
    " Transaction        : $TransactionId",
    " Provider           : $Provider",
    " Resource           : $ResourceType",
    " Operation          : $Operation",
    " Decision           : $decision",
    " Reason             : $reason",
    " Committed Matches  : $($committedMatches.Count)",
    " Ambiguous Matches  : $($ambiguousMatches.Count)",
    '',
    ' PROVIDER EXECUTION : NONE',
    ' SYSTEM MUTATION    : NONE',
    '',
    " JSON               : $json",
    " TXT                : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host "  JSON : $json"
Write-Host "  TXT  : $txt"
Write-Host ''
Write-Host '============================================================' -ForegroundColor $color
Write-Host " V2.7.8 IDEMPOTENCY GUARD : $decision" -ForegroundColor $color
Write-Host ' ZERO PROVIDER EXECUTION / ZERO SYSTEM MUTATION'
Write-Host '============================================================' -ForegroundColor $color
