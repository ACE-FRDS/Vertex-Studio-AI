#requires -Version 7.0
<#
VERTEX ENV-2 V2.7.12 — GATEWAY LINEAGE ENFORCEMENT
LINEAGE -> IDEMPOTENCY -> GATEWAY ADMISSION
ZERO PROVIDER EXECUTION / ZERO SYSTEM MUTATION

PURPOSE
  Make lineage/idempotency a mandatory admission layer before any provider gateway.

POLICY
  CANONICAL_COMMITTED                  -> DENY_ALREADY_COMMITTED
  SUPERSEDED_BY_COMMITTED_EXECUTION    -> DENY_SUPERSEDED
  ACTIVE_NON_TERMINAL                  -> CONTINUE_TO_GATEWAY
  Ambiguous / missing lineage          -> HOLD
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CandidateId,

    [string]$TransactionId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$CoreRoot   = Join-Path $ReportRoot '_transaction_core'

function Get-SafeProperty {
    param([AllowNull()]$Object,[Parameter(Mandatory)][string]$Name,$Default=$null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.7.12 — GATEWAY LINEAGE ENFORCEMENT' -ForegroundColor Magenta
Write-Host ' LINEAGE -> IDEMPOTENCY -> GATEWAY ADMISSION' -ForegroundColor Magenta
Write-Host ' ZERO PROVIDER EXECUTION / ZERO SYSTEM MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$lineageFile = Get-ChildItem -LiteralPath $CoreRoot -Filter 'VERTEX_TRANSACTION_LINEAGE.*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

$idempotencyFile = Get-ChildItem -LiteralPath $CoreRoot -Filter 'VERTEX_IDEMPOTENCY_GUARD.*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $lineageFile) { throw 'No transaction lineage report found.' }
if (-not $idempotencyFile) { throw 'No idempotency guard receipt found.' }

$lineage = Get-Content -LiteralPath $lineageFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$idem    = Get-Content -LiteralPath $idempotencyFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100

Write-Host ''
Write-Host '[1/4] LOAD SAFETY EVIDENCE' -ForegroundColor Cyan
Write-Host "  Lineage     : $($lineageFile.FullName)"
Write-Host "  Idempotency : $($idempotencyFile.FullName)"
Write-Host "  Candidate   : $CandidateId"
Write-Host "  Transaction : $TransactionId"

$lineageFacts = @($lineage.facts | Where-Object {
    ([string](Get-SafeProperty $_ 'candidate_id' '')) -eq $CandidateId
})

if ($TransactionId) {
    $txnFacts = @($lineageFacts | Where-Object {
        ([string](Get-SafeProperty $_ 'transaction_id' '')) -eq $TransactionId
    })
} else {
    $txnFacts = $lineageFacts
}

Write-Host ''
Write-Host '[2/4] LINEAGE ENFORCEMENT' -ForegroundColor Cyan

$states = @($txnFacts | ForEach-Object {
    [string](Get-SafeProperty $_ 'lineage_state' '')
} | Where-Object { $_ } | Select-Object -Unique)

foreach ($f in $txnFacts) {
    Write-Host "  $([string](Get-SafeProperty $f 'lineage_state' 'UNKNOWN')) : $([string](Get-SafeProperty $f 'transaction_id' ''))"
}

$idemDecision = [string](Get-SafeProperty $idem 'decision' '')
$idemCandidate = [string](Get-SafeProperty (Get-SafeProperty $idem 'request' $null) 'candidate_id' '')

Write-Host ''
Write-Host '[3/4] FINAL GATEWAY ADMISSION' -ForegroundColor Cyan
Write-Host "  Idempotency Decision : $idemDecision"

$decision = 'HOLD'
$reason = 'Safety evidence is insufficient.'

if ($txnFacts.Count -eq 0) {
    $decision = 'HOLD_LINEAGE_NOT_FOUND'
    $reason = 'No lineage fact matches the requested identity.'
}
elseif ($states -contains 'SUPERSEDED_BY_COMMITTED_EXECUTION') {
    $decision = 'DENY_SUPERSEDED'
    $reason = 'Requested transaction is superseded by an already committed execution.'
}
elseif ($states -contains 'CANONICAL_COMMITTED') {
    $decision = 'DENY_ALREADY_COMMITTED'
    $reason = 'Requested candidate/transaction is already committed and canonical.'
}
elseif ($idemCandidate -eq $CandidateId -and $idemDecision -eq 'DENY_ALREADY_COMMITTED') {
    $decision = 'DENY_ALREADY_COMMITTED'
    $reason = 'Idempotency guard proves a prior committed execution.'
}
elseif ($states.Count -eq 1 -and $states[0] -eq 'ACTIVE_NON_TERMINAL') {
    if ($idemCandidate -eq $CandidateId -and $idemDecision -eq 'ALLOW_FIRST_EXECUTION') {
        $decision = 'CONTINUE_TO_GATEWAY'
        $reason = 'Lineage is active/non-terminal and idempotency allows first execution.'
    } else {
        $decision = 'HOLD_IDEMPOTENCY_NOT_CLEAR'
        $reason = 'Active lineage exists but idempotency does not explicitly allow execution.'
    }
}
else {
    $decision = 'HOLD_AMBIGUOUS_LINEAGE'
    $reason = "Lineage states are ambiguous: $($states -join ', ')"
}

$color = if ($decision -eq 'CONTINUE_TO_GATEWAY') { 'Green' } elseif ($decision.StartsWith('DENY')) { 'Red' } else { 'Yellow' }

Write-Host "  DECISION : $decision" -ForegroundColor $color
Write-Host "  Reason   : $reason"
Write-Host '  Provider Invocation : NONE'

Write-Host ''
Write-Host '[4/4] ENFORCEMENT RECEIPT' -ForegroundColor Cyan

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $CoreRoot "VERTEX_GATEWAY_LINEAGE_ENFORCEMENT.$stamp.json"
$txt  = Join-Path $CoreRoot "VERTEX_GATEWAY_LINEAGE_ENFORCEMENT.$stamp.txt"

$receipt = [ordered]@{
    schema = 'vertex.transaction.gateway-lineage-enforcement.v1'
    version = '2.7.12'
    generated_at = (Get-Date).ToString('o')
    request = [ordered]@{
        candidate_id = $CandidateId
        transaction_id = $TransactionId
    }
    evidence = [ordered]@{
        lineage_report = $lineageFile.FullName
        idempotency_receipt = $idempotencyFile.FullName
        lineage_states = $states
        idempotency_decision = $idemDecision
    }
    decision = $decision
    reason = $reason
    policy = [ordered]@{
        canonical_committed = 'DENY'
        superseded = 'DENY'
        active_non_terminal = 'REQUIRE_IDEMPOTENCY_ALLOW'
        ambiguous = 'HOLD'
        provider_invocation = 'NONE'
        system_mutation = 'NONE'
    }
}

$receipt | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX GATEWAY LINEAGE ENFORCEMENT V2.7.12',
    '============================================================',
    " Candidate   : $CandidateId",
    " Transaction : $TransactionId",
    " States      : $($states -join ', ')",
    " Idempotency : $idemDecision",
    " Decision    : $decision",
    " Reason      : $reason",
    '',
    ' PROVIDER INVOCATION : NONE',
    ' SYSTEM MUTATION     : NONE',
    '',
    " JSON : $json",
    " TXT  : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host "  JSON : $json"
Write-Host "  TXT  : $txt"
Write-Host ''
Write-Host '============================================================' -ForegroundColor $color
Write-Host " V2.7.12 GATEWAY LINEAGE ENFORCEMENT : $decision" -ForegroundColor $color
Write-Host ' ZERO PROVIDER EXECUTION / ZERO SYSTEM MUTATION'
Write-Host '============================================================' -ForegroundColor $color
