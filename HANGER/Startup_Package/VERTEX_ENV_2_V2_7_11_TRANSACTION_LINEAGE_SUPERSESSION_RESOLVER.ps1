#requires -Version 7.0
<#
VERTEX ENV-2 V2.7.11 — TRANSACTION LINEAGE / SUPERSESSION RESOLVER
ZERO SYSTEM MUTATION / ZERO PROVIDER EXECUTION

PURPOSE
  Resolve lineage relationships among canonical transaction facts.

RULE
  For the same Candidate + Resource + Operation:
    - If a COMMITTED_VERIFIED execution exists,
      later pending/non-terminal intents become
      SUPERSEDED_BY_COMMITTED_EXECUTION.
    - Committed facts remain canonical.
    - Distinct candidates remain independent.

INPUT
  Latest V2.7.10 canonical execution identity report.

OUTPUT
  Transaction lineage graph / supersession decisions.
#>

[CmdletBinding()]
param(
    [string]$CandidateId = '',
    [string]$ResourceType = 'WINDOWS_FIREWALL_RULE',
    [string]$Operation = 'EXECUTE'
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
Write-Host ' VERTEX ENV-2 V2.7.11 — TRANSACTION LINEAGE RESOLVER' -ForegroundColor Magenta
Write-Host ' CANONICAL FACTS -> LINEAGE -> SUPERSESSION' -ForegroundColor Magenta
Write-Host ' ZERO SYSTEM MUTATION / ZERO PROVIDER EXECUTION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$source = Get-ChildItem -LiteralPath $CoreRoot -Filter 'VERTEX_CANONICAL_EXECUTION_IDENTITY.*.json' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $source) {
    throw 'No V2.7.10 canonical execution identity report found.'
}

$data = Get-Content -LiteralPath $source.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$facts = @($data.facts)

if ($CandidateId) {
    $facts = @($facts | Where-Object {
        [string](Get-SafeProperty $_ 'candidate_id' '') -eq $CandidateId
    })
}

Write-Host ''
Write-Host '[1/4] LOAD CANONICAL FACTS' -ForegroundColor Cyan
Write-Host "  Source      : $($source.FullName)"
Write-Host "  Facts       : $($facts.Count)"
Write-Host "  Candidate   : $CandidateId"
Write-Host "  Resource    : $ResourceType"
Write-Host "  Operation   : $Operation"

if ($facts.Count -eq 0) {
    throw 'No canonical facts matched scope.'
}

# Infer canonical committed fact(s)
$committedFacts = @($facts | Where-Object {
    [bool](Get-SafeProperty $_ 'committed_verified' $false)
})

$pendingFacts = @($facts | Where-Object {
    -not [bool](Get-SafeProperty $_ 'committed_verified' $false)
})

Write-Host ''
Write-Host '[2/4] LINEAGE CLASSIFICATION' -ForegroundColor Cyan
Write-Host "  Committed Facts : $($committedFacts.Count)"
Write-Host "  Pending Facts   : $($pendingFacts.Count)"

$results = [System.Collections.Generic.List[object]]::new()

# Choose primary committed fact by strongest evidence, then presence of execution_id.
$primaryCommitted = $null
if ($committedFacts.Count -gt 0) {
    $primaryCommitted = @(
        $committedFacts |
        Sort-Object `
            @{Expression={ [int](Get-SafeProperty $_ 'evidence_count' 0) };Descending=$true},
            @{Expression={ if([string]::IsNullOrWhiteSpace([string](Get-SafeProperty $_ 'execution_id' ''))){0}else{1} };Descending=$true}
    )[0]
}

foreach ($fact in $facts) {
    $key = [string](Get-SafeProperty $fact 'canonical_key' '')
    $executionId = [string](Get-SafeProperty $fact 'execution_id' '')
    $transactionId = [string](Get-SafeProperty $fact 'transaction_id' '')
    $candidate = [string](Get-SafeProperty $fact 'candidate_id' '')
    $committed = [bool](Get-SafeProperty $fact 'committed_verified' $false)
    $confidence = [string](Get-SafeProperty $fact 'confidence' '')
    $evidenceCount = [int](Get-SafeProperty $fact 'evidence_count' 0)

    $lineageState = 'ACTIVE_NON_TERMINAL'
    $supersededBy = ''
    $reason = 'No committed predecessor resolved.'

    if ($committed) {
        $lineageState = 'CANONICAL_COMMITTED'
        $reason = 'Committed and verified execution is canonical.'
    }
    elseif ($null -ne $primaryCommitted) {
        $primaryExec = [string](Get-SafeProperty $primaryCommitted 'execution_id' '')
        $primaryTxn  = [string](Get-SafeProperty $primaryCommitted 'transaction_id' '')

        $lineageState = 'SUPERSEDED_BY_COMMITTED_EXECUTION'
        $supersededBy = if ($primaryExec) { $primaryExec } else { $primaryTxn }
        $reason = 'Same scoped intent has an already committed/verified execution.'
    }

    $results.Add([pscustomobject][ordered]@{
        canonical_key = $key
        candidate_id = $candidate
        transaction_id = $transactionId
        execution_id = $executionId
        committed_verified = $committed
        confidence = $confidence
        evidence_count = $evidenceCount
        resource_type = $ResourceType
        operation = $Operation
        lineage_state = $lineageState
        superseded_by = $supersededBy
        reason = $reason
    })

    $color = switch ($lineageState) {
        'CANONICAL_COMMITTED' { 'Green' }
        'SUPERSEDED_BY_COMMITTED_EXECUTION' { 'Yellow' }
        default { 'Cyan' }
    }

    Write-Host "  [$lineageState] $key" -ForegroundColor $color
    Write-Host "    Txn        : $transactionId"
    Write-Host "    Exec       : $executionId"
    Write-Host "    Superseded : $supersededBy"
    Write-Host "    Reason     : $reason"
}

Write-Host ''
Write-Host '[3/4] SUPERSESSION SUMMARY' -ForegroundColor Cyan

$counts = [ordered]@{
    total = $results.Count
    canonical_committed = @($results | Where-Object lineage_state -eq 'CANONICAL_COMMITTED').Count
    superseded = @($results | Where-Object lineage_state -eq 'SUPERSEDED_BY_COMMITTED_EXECUTION').Count
    active_non_terminal = @($results | Where-Object lineage_state -eq 'ACTIVE_NON_TERMINAL').Count
}

Write-Host "  Total               : $($counts.total)"
Write-Host "  Canonical Committed : $($counts.canonical_committed)"
Write-Host "  Superseded          : $($counts.superseded)"
Write-Host "  Active Non-Terminal : $($counts.active_non_terminal)"

Write-Host ''
Write-Host '[4/4] LINEAGE RECEIPT' -ForegroundColor Cyan

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $CoreRoot "VERTEX_TRANSACTION_LINEAGE.$stamp.json"
$txt  = Join-Path $CoreRoot "VERTEX_TRANSACTION_LINEAGE.$stamp.txt"

$report = [ordered]@{
    schema = 'vertex.transaction.lineage.v1'
    version = '2.7.11'
    generated_at = (Get-Date).ToString('o')
    source = $source.FullName
    scope = [ordered]@{
        candidate_id = $CandidateId
        resource_type = $ResourceType
        operation = $Operation
    }
    counts = $counts
    facts = @($results)
    policy = [ordered]@{
        committed_execution_is_canonical = $true
        pending_same_intent_is_superseded = $true
        superseded_provider_execution = 'DENY'
        system_mutation = 'NONE'
        provider_execution = 'NONE'
    }
}

$report | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX TRANSACTION LINEAGE V2.7.11',
    '============================================================',
    " Candidate           : $CandidateId",
    " Resource            : $ResourceType",
    " Operation           : $Operation",
    " Total               : $($counts.total)",
    " Canonical Committed : $($counts.canonical_committed)",
    " Superseded          : $($counts.superseded)",
    " Active Non-Terminal : $($counts.active_non_terminal)",
    '',
    $(foreach ($r in $results) {
        " $($r.lineage_state) | Candidate=$($r.candidate_id) | Txn=$($r.transaction_id) | Exec=$($r.execution_id) | SupersededBy=$($r.superseded_by)"
    }),
    '',
    ' SYSTEM MUTATION    : NONE',
    ' PROVIDER EXECUTION : NONE',
    '',
    " JSON : $json",
    " TXT  : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host "  JSON : $json"
Write-Host "  TXT  : $txt"

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' V2.7.11 TRANSACTION LINEAGE : GREEN' -ForegroundColor Green
Write-Host " CANONICAL  : $($counts.canonical_committed)"
Write-Host " SUPERSEDED : $($counts.superseded)"
Write-Host ' ZERO SYSTEM MUTATION / ZERO PROVIDER EXECUTION'
Write-Host '============================================================' -ForegroundColor Green
