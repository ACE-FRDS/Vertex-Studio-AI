#requires -Version 7.0
<#
VERTEX ENV-2 V1.8 — REGISTRY SAFE ROLLBACK

DEFAULT: DryRun

Eligible:
  ownership == VERTEX_CREATED
  rollback_eligible == true
  current registry value == ledger vertex_value

Denied:
  PRE_EXISTING_NOT_OWNED
  VERTEX_MODIFIED
  THIRD_PARTY_CHANGED
  CONFLICT / UNVERIFIED
  HKLM
  any key outside HKCU:\Software\VertexProtocol\EnvTest\

Execute behavior:
  1. delete eligible Vertex-created value
  2. verify value is absent
  3. if dedicated test key is empty, remove that exact key only
  4. update ledger to ROLLED_BACK
#>

param(
    [ValidateSet('DryRun','Execute')]
    [string]$Mode='DryRun',

    [string]$Approval='',

    [string]$PackageId='vertex.env2.registry-positive.v1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$RequiredApproval='APPROVE-REGISTRY-ROLLBACK'

$ReportRoot='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$RegistryRoot=Join-Path $ReportRoot '_registry'
$LedgerPath=Join-Path $RegistryRoot 'VERTEX_REGISTRY_OWNERSHIP_LEDGER.json'

function P {
    param($Object,[string]$Name,$Default=$null)
    if($null -eq $Object){ return $Default }
    $p=$Object.PSObject.Properties[$Name]
    if($null -eq $p){ return $Default }
    return $p.Value
}

function Read-Reg {
    param([string]$Key,[string]$Name)

    $r=[ordered]@{
        key_exists=$false
        value_exists=$false
        value=$null
        kind=$null
    }

    if(-not(Test-Path -LiteralPath $Key)){
        return [pscustomobject]$r
    }

    $r.key_exists=$true
    $item=Get-Item -LiteralPath $Key -ErrorAction Stop
    $names=@($item.GetValueNames())

    if($names -contains $Name){
        $r.value_exists=$true
        $r.value=$item.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $r.kind=[string]$item.GetValueKind($Name)
    }

    return [pscustomobject]$r
}

function Values-Equal {
    param($A,$B)

    if($null -eq $A -and $null -eq $B){ return $true }
    if($null -eq $A -or $null -eq $B){ return $false }

    if($A -is [array] -or $B -is [array]){
        return ((@($A)|ConvertTo-Json -Compress) -eq (@($B)|ConvertTo-Json -Compress))
    }

    return ([string]$A -ceq [string]$B)
}

function Key-IsEmpty {
    param([string]$KeyPath)

    if(-not(Test-Path -LiteralPath $KeyPath)){ return $true }

    $key=Get-Item -LiteralPath $KeyPath -ErrorAction Stop
    $valueNames=@($key.GetValueNames())
    $subKeys=@($key.GetSubKeyNames())

    return ($valueNames.Count -eq 0 -and $subKeys.Count -eq 0)
}

if(-not(Test-Path -LiteralPath $LedgerPath -PathType Leaf)){
    throw "Registry ownership ledger not found: $LedgerPath"
}

$ledger=Get-Content -LiteralPath $LedgerPath -Raw -Encoding utf8 | ConvertFrom-Json
$records=@(P $ledger 'records' @())

$targets=@(
    $records | Where-Object {
        [string](P $_ 'package_id' '') -eq $PackageId -and
        [string](P $_ 'ownership' '') -eq 'VERTEX_CREATED' -and
        [bool](P $_ 'rollback_eligible' $false)
    }
)

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V1.8 — REGISTRY SAFE ROLLBACK' -ForegroundColor Magenta
Write-Host ' OWNERSHIP -> LIVE MATCH -> HUMAN GATE -> CLEAN DEPARTURE' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ("Mode      : {0}" -f $Mode)
Write-Host ("Package   : {0}" -f $PackageId)
Write-Host ("Targets   : {0}" -f $targets.Count)

if($targets.Count -eq 0){
    throw "No rollback-eligible registry assets for package: $PackageId"
}

if($Mode -eq 'Execute' -and $Approval -ne $RequiredApproval){
    throw "HUMAN GATE RED: Execute requires -Approval $RequiredApproval"
}

$results=@()
$index=0

foreach($record in $targets){
    $index++

    $keyPath=[string](P $record 'key_path' '')
    $valueName=[string](P $record 'value_name' '')
    $vertexValue=P $record 'vertex_value' $null

    if($keyPath -notlike 'HKCU:\Software\VertexProtocol\EnvTest\*'){
        throw "SAFETY RED: registry path outside Vertex EnvTest namespace: $keyPath"
    }

    $live=Read-Reg -Key $keyPath -Name $valueName

    $result=[ordered]@{
        index=$index
        key_path=$keyPath
        value_name=$valueName
        status='PENDING'
        action='NONE'
        value_removed=$false
        key_removed=$false
        reason=$null
    }

    Write-Host ''
    Write-Host ("[{0}/{1}] {2} -> {3}" -f $index,$targets.Count,$keyPath,$valueName) -ForegroundColor Yellow

    if(-not $live.value_exists){
        $result.status='ALREADY_ABSENT'
        $result.reason='Registry value is already absent.'
        Write-Host '  ALREADY_ABSENT' -ForegroundColor DarkYellow
        $results += [pscustomobject]$result
        continue
    }

    if(-not(Values-Equal $live.value $vertexValue)){
        $result.status='RED'
        $result.action='DENY'
        $result.reason='Current value differs from Vertex-owned value.'
        Write-Host '  RED — THIRD PARTY / HUMAN CHANGE DETECTED' -ForegroundColor Red
        $results += [pscustomobject]$result
        continue
    }

    $result.action='DELETE_VERTEX_CREATED_VALUE'

    if($Mode -eq 'DryRun'){
        $result.status='DRY_RUN'
        Write-Host '  DRY_RUN — DELETE_VERTEX_CREATED_VALUE' -ForegroundColor Green
        $results += [pscustomobject]$result
        continue
    }

    Remove-ItemProperty -LiteralPath $keyPath -Name $valueName -ErrorAction Stop

    $afterValue=Read-Reg -Key $keyPath -Name $valueName
    if($afterValue.value_exists){
        throw "POST-ROLLBACK VERIFY RED: registry value still exists: $keyPath -> $valueName"
    }

    $result.value_removed=$true

    if(Key-IsEmpty $keyPath){
        Remove-Item -LiteralPath $keyPath -Force -ErrorAction Stop

        if(Test-Path -LiteralPath $keyPath){
            throw "POST-ROLLBACK VERIFY RED: empty Vertex test key still exists: $keyPath"
        }

        $result.key_removed=$true
    }

    $result.status='ROLLED_BACK'
    Write-Host '  ROLLED_BACK' -ForegroundColor Green

    $results += [pscustomobject]$result
}

$red=@($results | Where-Object status -eq 'RED')

if($red.Count -gt 0){
    throw "REGISTRY ROLLBACK RED: $($red.Count) target(s) denied."
}

if($Mode -eq 'Execute'){
    $updated=@()

    foreach($record in $records){
        $keyPath=[string](P $record 'key_path' '')
        $valueName=[string](P $record 'value_name' '')

        $match=$results | Where-Object {
            $_.key_path -eq $keyPath -and
            $_.value_name -eq $valueName
        } | Select-Object -First 1

        if($match -and $match.status -in @('ROLLED_BACK','ALREADY_ABSENT')){
            $record.ownership='ROLLED_BACK'
            $record.rollback_eligible=$false
            $record | Add-Member -NotePropertyName rolled_back_at -NotePropertyValue (Get-Date).ToString('o') -Force
            $record | Add-Member -NotePropertyName rollback_status -NotePropertyValue $match.status -Force
        }

        $updated += $record
    }

    $newLedger=[ordered]@{
        schema=[string](P $ledger 'schema' 'vertex.registry.ownership-ledger.v1')
        updated_at=(Get-Date).ToString('o')
        records=$updated
        notes=@(
            'Registry ownership is evidence-based.',
            'Vertex-created values may be removed only while unchanged.',
            'Third-party changes block automatic rollback.'
        )
    }

    $newLedger | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $LedgerPath -Encoding utf8
}

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$receiptPath=Join-Path $ReportRoot "VERTEX_REGISTRY_ROLLBACK_RECEIPT.$stamp.json"

$receipt=[ordered]@{
    schema='vertex.registry.rollback-receipt.v1'
    package_id=$PackageId
    mode=$Mode
    status=if($Mode -eq 'Execute'){'ROLLBACK_GREEN'}else{'DRY_RUN_GREEN'}
    generated_at=(Get-Date).ToString('o')
    approval_verified=($Mode -eq 'Execute' -and $Approval -eq $RequiredApproval)
    ledger_path=$LedgerPath
    results=$results
    safety=[ordered]@{
        scope='HKCU_VERTEX_ENVTEST_ONLY'
        hklm='DENIED'
        third_party_changed='DENIED'
        pre_existing='DENIED'
        parent_namespace_delete='DENIED'
    }
}

$receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receiptPath -Encoding utf8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' VERTEX REGISTRY SAFE ROLLBACK RESULT' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ("Status    : {0}" -f $receipt.status)
Write-Host ("Receipt   : {0}" -f $receiptPath)
Write-Host ("Ledger    : {0}" -f $LedgerPath)
Write-Host '============================================================' -ForegroundColor Green
