#requires -Version 7.0
<#
VERTEX ENV-2 V2.7.10 — EVIDENCE DEDUP / CANONICAL EXECUTION IDENTITY
LEDGER + POST-COMMIT + GATEWAY -> CANONICAL EXECUTION FACTS
ZERO SYSTEM MUTATION / ZERO PROVIDER EXECUTION

PURPOSE
  Multiple evidence sources may describe the same execution.
  Collapse those observations into one canonical execution fact.

CANONICAL KEY PRIORITY
  1. execution_id
  2. transaction_id + candidate_id
  3. evidence fingerprint fallback

This is evidence normalization only. It does not alter the system or provider.
#>

[CmdletBinding()]
param(
    [string]$CandidateId = '',
    [string]$TransactionId = ''
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

function Add-Evidence {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$SourceType,
        [string]$SourcePath,
        [AllowNull()]$Object
    )

    if ($null -eq $Object) { return }

    $candidate = [string](Get-SafeProperty $Object 'candidate_id' '')
    $txn       = [string](Get-SafeProperty $Object 'transaction_id' '')
    $exec      = [string](Get-SafeProperty $Object 'execution_id' '')
    $status    = [string](Get-SafeProperty $Object 'status' '')
    $lifecycle = [string](Get-SafeProperty $Object 'lifecycle_state' '')

    if (-not $lifecycle) {
        $lifecycle = [string](Get-SafeProperty $Object 'transaction_lifecycle' '')
    }
    if (-not $lifecycle) {
        $lifecycle = [string](Get-SafeProperty $Object 'lifecycle' '')
    }

    $verification = [string](Get-SafeProperty $Object 'verification_status' '')

    $List.Add([pscustomobject]@{
        source_type = $SourceType
        source_path = $SourcePath
        candidate_id = $candidate
        transaction_id = $txn
        execution_id = $exec
        status = $status
        lifecycle = $lifecycle
        verification_status = $verification
    })
}

function Get-CanonicalKey {
    param($Evidence)

    if (-not [string]::IsNullOrWhiteSpace($Evidence.execution_id)) {
        return "EXEC::$($Evidence.execution_id)"
    }

    if (-not [string]::IsNullOrWhiteSpace($Evidence.transaction_id) -and
        -not [string]::IsNullOrWhiteSpace($Evidence.candidate_id)) {
        return "TXN_CAND::$($Evidence.transaction_id)::$($Evidence.candidate_id)"
    }

    $raw = "$($Evidence.source_type)|$($Evidence.source_path)|$($Evidence.candidate_id)|$($Evidence.transaction_id)|$($Evidence.status)"
    $bytes = [Text.Encoding]::UTF8.GetBytes($raw)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return "FALLBACK::$([Convert]::ToHexString($hash))"
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.7.10 — CANONICAL EXECUTION IDENTITY' -ForegroundColor Magenta
Write-Host ' EVIDENCE -> DEDUP -> ONE EXECUTION FACT' -ForegroundColor Magenta
Write-Host ' ZERO SYSTEM MUTATION / ZERO PROVIDER EXECUTION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$evidence = [System.Collections.Generic.List[object]]::new()

Write-Host ''
Write-Host '[1/4] COLLECT EVIDENCE' -ForegroundColor Cyan

# Transaction ledger
if (Test-Path -LiteralPath $LedgerPath -PathType Leaf) {
    $ledger = Get-Content -LiteralPath $LedgerPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100

    if ($ledger -is [System.Array]) {
        $records = @($ledger)
    } else {
        $recordsProp = Get-SafeProperty $ledger 'records' $null
        $entriesProp = Get-SafeProperty $ledger 'entries' $null
        $txnsProp = Get-SafeProperty $ledger 'transactions' $null

        if ($null -ne $recordsProp) { $records = @($recordsProp) }
        elseif ($null -ne $entriesProp) { $records = @($entriesProp) }
        elseif ($null -ne $txnsProp) { $records = @($txnsProp) }
        else { $records = @($ledger) }
    }

    foreach ($r in $records) {
        Add-Evidence -List $evidence -SourceType 'TRANSACTION_LEDGER' -SourcePath $LedgerPath -Object $r
    }
}

# Post-commit verification reports
foreach ($file in @(Get-ChildItem -LiteralPath $ReportRoot -Filter 'VERTEX_POST_COMMIT_VERIFICATION.*.json' -File -ErrorAction SilentlyContinue)) {
    try {
        $r = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
        Add-Evidence -List $evidence -SourceType 'POST_COMMIT_VERIFICATION' -SourcePath $file.FullName -Object $r
    } catch {}
}

# Gateway receipts
foreach ($file in @(Get-ChildItem -LiteralPath $CoreRoot -Filter 'VERTEX_PROVIDER_INVOCATION_GATEWAY.*.json' -File -ErrorAction SilentlyContinue)) {
    try {
        $r = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
        Add-Evidence -List $evidence -SourceType 'PROVIDER_GATEWAY' -SourcePath $file.FullName -Object $r
    } catch {}
}

# Optional scope filter
$scoped = @($evidence | Where-Object {
    $candidateOK = [string]::IsNullOrWhiteSpace($CandidateId) -or $_.candidate_id -eq $CandidateId
    $txnOK = [string]::IsNullOrWhiteSpace($TransactionId) -or $_.transaction_id -eq $TransactionId
    $candidateOK -and $txnOK
})

Write-Host "  Raw Evidence : $($evidence.Count)"
Write-Host "  Scoped       : $($scoped.Count)"
Write-Host "  Candidate    : $CandidateId"
Write-Host "  Transaction  : $TransactionId"

Write-Host ''
Write-Host '[2/4] CANONICALIZE IDENTITIES' -ForegroundColor Cyan

$groups = @{}

foreach ($e in $scoped) {
    $key = Get-CanonicalKey $e

    # If an evidence item lacks execution_id but matches a known transaction/candidate
    # pair that already has an execution_id, merge it into that execution.
    if ($key.StartsWith('TXN_CAND::')) {
        $existingKey = $null
        foreach ($k in $groups.Keys) {
            if ($k.StartsWith('EXEC::')) {
                $first = $groups[$k][0]
                if ($first.transaction_id -eq $e.transaction_id -and
                    $first.candidate_id -eq $e.candidate_id) {
                    $existingKey = $k
                    break
                }
            }
        }
        if ($existingKey) { $key = $existingKey }
    }

    if (-not $groups.ContainsKey($key)) {
        $groups[$key] = [System.Collections.Generic.List[object]]::new()
    }
    $groups[$key].Add($e)
}

# Second pass: merge TXN_CAND groups into EXEC groups if the pair matches.
foreach ($key in @($groups.Keys)) {
    if (-not $key.StartsWith('TXN_CAND::')) { continue }
    $sample = $groups[$key][0]
    $target = $null

    foreach ($k2 in @($groups.Keys)) {
        if (-not $k2.StartsWith('EXEC::')) { continue }
        $s2 = $groups[$k2][0]
        if ($s2.transaction_id -eq $sample.transaction_id -and
            $s2.candidate_id -eq $sample.candidate_id) {
            $target = $k2
            break
        }
    }

    if ($target) {
        foreach ($item in $groups[$key]) {
            $groups[$target].Add($item)
        }
        $groups.Remove($key)
    }
}

Write-Host "  Canonical Executions : $($groups.Count)"

Write-Host ''
Write-Host '[3/4] BUILD CANONICAL FACTS' -ForegroundColor Cyan

$facts = [System.Collections.Generic.List[object]]::new()

foreach ($key in ($groups.Keys | Sort-Object)) {
    $items = @($groups[$key])

    $exec = @($items.execution_id | Where-Object { $_ } | Select-Object -Unique)
    $txns = @($items.transaction_id | Where-Object { $_ } | Select-Object -Unique)
    $cands = @($items.candidate_id | Where-Object { $_ } | Select-Object -Unique)

    $committed = @($items | Where-Object {
        $_.status -in @('COMMIT_GREEN','COMMITTED_VERIFIED','POST_COMMIT_GREEN') -or
        $_.lifecycle -eq 'COMMITTED_VERIFIED' -or
        $_.verification_status -eq 'POST_COMMIT_GREEN'
    }).Count -gt 0

    $confidence = if ($committed -and $items.Count -ge 2) {
        'CORROBORATED'
    } elseif ($committed) {
        'PROVEN_SINGLE_SOURCE'
    } else {
        'OBSERVED_NOT_TERMINAL'
    }

    $fact = [pscustomobject][ordered]@{
        canonical_key = $key
        execution_id = if ($exec.Count) { $exec[0] } else { '' }
        transaction_id = if ($txns.Count) { $txns[0] } else { '' }
        candidate_id = if ($cands.Count) { $cands[0] } else { '' }
        committed_verified = $committed
        confidence = $confidence
        evidence_count = $items.Count
        evidence_sources = @($items.source_type | Select-Object -Unique)
        evidence = $items
    }

    $facts.Add($fact)

    Write-Host "  FACT : $key"
    Write-Host "    Execution : $($fact.execution_id)"
    Write-Host "    Txn       : $($fact.transaction_id)"
    Write-Host "    Candidate : $($fact.candidate_id)"
    Write-Host "    Committed : $($fact.committed_verified)"
    Write-Host "    Confidence: $($fact.confidence)"
    Write-Host "    Evidence  : $($fact.evidence_count)"
}

Write-Host ''
Write-Host '[4/4] CANONICAL FACT RECEIPT' -ForegroundColor Cyan

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $CoreRoot "VERTEX_CANONICAL_EXECUTION_IDENTITY.$stamp.json"
$txt  = Join-Path $CoreRoot "VERTEX_CANONICAL_EXECUTION_IDENTITY.$stamp.txt"

$result = [ordered]@{
    schema = 'vertex.transaction.canonical-execution-identity.v1'
    version = '2.7.10'
    generated_at = (Get-Date).ToString('o')
    scope = [ordered]@{
        candidate_id = $CandidateId
        transaction_id = $TransactionId
    }
    raw_evidence_count = $scoped.Count
    canonical_execution_count = $facts.Count
    facts = @($facts)
    safety = [ordered]@{
        system_mutation = 'NONE'
        provider_execution = 'NONE'
        evidence_normalization_only = $true
    }
}

$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX CANONICAL EXECUTION IDENTITY V2.7.10',
    '============================================================',
    " Candidate            : $CandidateId",
    " Transaction          : $TransactionId",
    " Raw Evidence         : $($scoped.Count)",
    " Canonical Executions : $($facts.Count)",
    '',
    $(foreach ($f in $facts) {
        " $($f.canonical_key) | Candidate=$($f.candidate_id) | Txn=$($f.transaction_id) | Exec=$($f.execution_id) | Committed=$($f.committed_verified) | Confidence=$($f.confidence) | Evidence=$($f.evidence_count)"
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
Write-Host ' V2.7.10 CANONICAL EXECUTION IDENTITY : GREEN' -ForegroundColor Green
Write-Host " RAW EVIDENCE : $($scoped.Count)"
Write-Host " EXECUTIONS   : $($facts.Count)"
Write-Host ' ZERO SYSTEM MUTATION / ZERO PROVIDER EXECUTION'
Write-Host '============================================================' -ForegroundColor Green
