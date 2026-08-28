#requires -Version 7.0
<#
VERTEX ENV-2 V1.4
SAFE ROLLBACK / UNINSTALLER FOUNDATION

DEFAULT: DryRun

TARGET ELIGIBILITY:
  ownership == VERTEX_CREATED
  rollback_eligible == true

V1.4 ALLOWED:
  - Remove Vertex-created empty directory
  - Remove Vertex-created file only if current SHA256 matches ledger SHA256

V1.4 DENIED:
  - Remove non-empty directory
  - Remove directory_tree
  - Remove PRE_EXISTING_NOT_OWNED
  - Remove CONFLICT / UNVERIFIED
  - Remove assets owned by another package
  - Registry / Service / Firewall / PATH / Driver mutation
  - Arbitrary command execution
#>

param(
    [ValidateSet('DryRun','Execute')]
    [string]$Mode = 'DryRun',

    [string]$Approval = '',

    [string]$PackageId = 'vertex.env2.ownership-positive.v1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RequiredApproval = 'APPROVE-ROLLBACK'

function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $Default }
    return $p.Value
}

function Get-Sha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Normalize-PathString {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    try { return [IO.Path]::GetFullPath($Path).TrimEnd('\') }
    catch { return $Path.TrimEnd('\') }
}

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$LedgerPath = Join-Path $ReportRoot '_ownership\VERTEX_PACKAGE_OWNERSHIP_LEDGER.json'

if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) {
    throw "Ownership ledger not found: $LedgerPath"
}

$ledger = Get-Content -LiteralPath $LedgerPath -Raw -Encoding utf8 | ConvertFrom-Json
$records = @(Get-Prop $ledger 'records' @())

$targets = @(
    $records | Where-Object {
        [string](Get-Prop $_ 'package_id' '') -eq $PackageId -and
        [string](Get-Prop $_ 'ownership' '') -eq 'VERTEX_CREATED' -and
        [bool](Get-Prop $_ 'rollback_eligible' $false)
    }
)

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V1.4 — SAFE ROLLBACK FOUNDATION' -ForegroundColor Magenta
Write-Host ' OWNERSHIP LEDGER -> DRY RUN -> HUMAN GATE -> ROLLBACK' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ("Mode      : {0}" -f $Mode) -ForegroundColor Green
Write-Host ("Package   : {0}" -f $PackageId) -ForegroundColor Green
Write-Host ("Targets   : {0}" -f $targets.Count) -ForegroundColor Green

if ($targets.Count -eq 0) {
    throw "No rollback-eligible VERTEX_CREATED assets found for package: $PackageId"
}

if ($Mode -eq 'Execute' -and $Approval -ne $RequiredApproval) {
    throw "HUMAN GATE RED: Execute requires -Approval $RequiredApproval"
}

$results = @()
$index = 0

foreach ($record in $targets) {
    $index++
    $path = Normalize-PathString ([string](Get-Prop $record 'path' ''))
    $assetType = [string](Get-Prop $record 'asset_type' '')
    $ledgerHash = [string](Get-Prop $record 'sha256' '')
    $exists = Test-Path -LiteralPath $path

    $result = [ordered]@{
        index = $index
        path = $path
        asset_type = $assetType
        eligible = $true
        exists_before = $exists
        action = 'NONE'
        status = 'PENDING'
        reason = $null
        removed = $false
    }

    Write-Host ("[{0}/{1}] {2}" -f $index, $targets.Count, $path) -ForegroundColor Yellow

    if (-not $exists) {
        $result.action = 'NONE'
        $result.status = 'ALREADY_ABSENT'
        $result.reason = 'Asset no longer exists.'
        Write-Host '  ALREADY_ABSENT' -ForegroundColor DarkYellow
        $results += [pscustomobject]$result
        continue
    }

    switch ($assetType) {
        'directory' {
            $children = @(Get-ChildItem -LiteralPath $path -Force -ErrorAction Stop)

            if ($children.Count -gt 0) {
                $result.action = 'DENIED'
                $result.status = 'RED'
                $result.reason = 'Directory is not empty.'
                Write-Host '  RED — NON-EMPTY DIRECTORY' -ForegroundColor Red
                $results += [pscustomobject]$result
                continue
            }

            $result.action = 'REMOVE_EMPTY_DIRECTORY'

            if ($Mode -eq 'DryRun') {
                $result.status = 'DRY_RUN'
                Write-Host '  DRY_RUN — REMOVE_EMPTY_DIRECTORY' -ForegroundColor Green
            }
            else {
                Remove-Item -LiteralPath $path -Force
                if (Test-Path -LiteralPath $path) {
                    throw "Rollback verification RED: directory still exists: $path"
                }

                $result.status = 'ROLLED_BACK'
                $result.removed = $true
                Write-Host '  ROLLED_BACK' -ForegroundColor Green
            }
        }

        'file' {
            $currentHash = Get-Sha256 $path

            if ([string]::IsNullOrWhiteSpace($ledgerHash)) {
                $result.action = 'DENIED'
                $result.status = 'RED'
                $result.reason = 'Ledger SHA256 missing.'
                Write-Host '  RED — LEDGER HASH MISSING' -ForegroundColor Red
                $results += [pscustomobject]$result
                continue
            }

            if ($currentHash -ne $ledgerHash) {
                $result.action = 'DENIED'
                $result.status = 'RED'
                $result.reason = 'Current SHA256 differs from ledger.'
                Write-Host '  RED — FILE CHANGED SINCE INSTALL' -ForegroundColor Red
                $results += [pscustomobject]$result
                continue
            }

            $result.action = 'REMOVE_VERIFIED_FILE'

            if ($Mode -eq 'DryRun') {
                $result.status = 'DRY_RUN'
                Write-Host '  DRY_RUN — REMOVE_VERIFIED_FILE' -ForegroundColor Green
            }
            else {
                Remove-Item -LiteralPath $path -Force
                if (Test-Path -LiteralPath $path) {
                    throw "Rollback verification RED: file still exists: $path"
                }

                $result.status = 'ROLLED_BACK'
                $result.removed = $true
                Write-Host '  ROLLED_BACK' -ForegroundColor Green
            }
        }

        'directory_tree' {
            $result.action = 'DENIED'
            $result.status = 'RED'
            $result.reason = 'directory_tree rollback is not enabled in V1.4.'
            Write-Host '  RED — TREE DELETE DENIED IN V1.4' -ForegroundColor Red
        }

        default {
            $result.action = 'DENIED'
            $result.status = 'RED'
            $result.reason = "Unsupported asset type: $assetType"
            Write-Host '  RED — UNSUPPORTED ASSET TYPE' -ForegroundColor Red
        }
    }

    $results += [pscustomobject]$result
}

$red = @($results | Where-Object { $_.status -eq 'RED' })
if ($red.Count -gt 0) {
    Write-Host ''
    Write-Host ("ROLLBACK GATE RED: {0} target(s) denied." -f $red.Count) -ForegroundColor Red
    throw 'Rollback aborted because one or more targets are unsafe.'
}

if ($Mode -eq 'Execute') {
    # Update only records successfully rolled back or already absent.
    $updatedRecords = @()

    foreach ($record in $records) {
        $path = Normalize-PathString ([string](Get-Prop $record 'path' ''))
        $match = $results | Where-Object { $_.path -ieq $path } | Select-Object -First 1

        if ($match -and $match.status -in @('ROLLED_BACK','ALREADY_ABSENT')) {
            $record.rollback_eligible = $false
            $record.ownership = 'ROLLED_BACK'
            $record | Add-Member -NotePropertyName rolled_back_at -NotePropertyValue (Get-Date).ToString('o') -Force
            $record | Add-Member -NotePropertyName rollback_status -NotePropertyValue $match.status -Force
        }

        $updatedRecords += $record
    }

    $newLedger = [ordered]@{
        schema = [string](Get-Prop $ledger 'schema' 'vertex.environment.ownership-ledger.v1')
        updated_at = (Get-Date).ToString('o')
        records = $updatedRecords
    }

    $newLedger | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $LedgerPath -Encoding utf8
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$receiptPath = Join-Path $ReportRoot "VERTEX_ROLLBACK_RECEIPT.$stamp.json"

$receipt = [ordered]@{
    schema = 'vertex.environment.rollback-receipt.v1'
    package_id = $PackageId
    mode = $Mode
    generated_at = (Get-Date).ToString('o')
    approval_verified = ($Mode -eq 'Execute' -and $Approval -eq $RequiredApproval)
    ledger_path = $LedgerPath
    results = $results
    status = if ($Mode -eq 'Execute') { 'ROLLBACK_GREEN' } else { 'DRY_RUN_GREEN' }
}

$receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receiptPath -Encoding utf8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' VERTEX SAFE ROLLBACK RESULT' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ("Status    : {0}" -f $receipt.status) -ForegroundColor Green
Write-Host ("Receipt   : {0}" -f $receiptPath) -ForegroundColor Green
Write-Host ("Ledger    : {0}" -f $LedgerPath) -ForegroundColor Green
Write-Host ''
Write-Host 'SAFETY BOUNDARY' -ForegroundColor Yellow
Write-Host '  PRE_EXISTING delete : DENIED'
Write-Host '  Non-empty dir       : DENIED'
Write-Host '  Tree delete         : DENIED'
Write-Host '  Changed file        : DENIED'
Write-Host '  Registry            : DENIED'
Write-Host '  Services            : DENIED'
Write-Host '  Firewall            : DENIED'
Write-Host '  PATH / Env          : DENIED'
Write-Host '============================================================' -ForegroundColor Green
