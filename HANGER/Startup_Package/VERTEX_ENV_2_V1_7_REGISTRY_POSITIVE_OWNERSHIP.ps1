#requires -Version 7.0
<#
VERTEX ENV-2 V1.7 — REGISTRY POSITIVE OWNERSHIP CASE

Purpose:
  Create ONE dedicated HKCU Vertex test value,
  capture before/after evidence,
  and register VERTEX_CREATED ownership.

Safety:
  - HKCU only
  - VertexProtocol\EnvTest namespace only
  - no HKLM
  - no service/firewall/PATH mutation
  - no arbitrary registry path
  - DryRun default
#>

param(
    [ValidateSet('DryRun','Execute')]
    [string]$Mode='DryRun',

    [string]$Approval=''
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$RequiredApproval='APPROVE-REGISTRY-TEST'
$KeyPath='HKCU:\Software\VertexProtocol\EnvTest\RegistryOwnership_20260823_224223'
$ValueName='VertexOwnedValue'
$VertexValue='VERTEX_REGISTRY_TEST_20260823_224223'

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

    $result=[ordered]@{
        key_exists=$false
        value_exists=$false
        value=$null
        kind=$null
    }

    if(-not(Test-Path -LiteralPath $Key)){
        return [pscustomobject]$result
    }

    $result.key_exists=$true
    $item=Get-Item -LiteralPath $Key -ErrorAction Stop
    $names=@($item.GetValueNames())

    if($names -contains $Name){
        $result.value_exists=$true
        $result.value=$item.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $result.kind=[string]$item.GetValueKind($Name)
    }

    return [pscustomobject]$result
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V1.7 — REGISTRY POSITIVE OWNERSHIP CASE' -ForegroundColor Magenta
Write-Host ' HKCU ONLY / HUMAN GATE / OWNERSHIP EVIDENCE' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ("Mode      : {0}" -f $Mode)
Write-Host ("Key       : {0}" -f $KeyPath)
Write-Host ("Value     : {0}" -f $ValueName)

if($KeyPath -notlike 'HKCU:\Software\VertexProtocol\EnvTest\*'){
    throw 'SAFETY RED: Registry path escaped the dedicated Vertex EnvTest namespace.'
}

$before=Read-Reg -Key $KeyPath -Name $ValueName

Write-Host ''
Write-Host ("Before key exists   : {0}" -f $before.key_exists)
Write-Host ("Before value exists : {0}" -f $before.value_exists)

if($before.value_exists){
    throw 'POSITIVE CASE RED: Test value already exists. Refusing overwrite.'
}

if($Mode -eq 'DryRun'){
    Write-Host ''
    Write-Host 'DRY RUN GREEN — would create dedicated HKCU test value.' -ForegroundColor Green
    Write-Host 'Registry remains untouched.' -ForegroundColor Green
    exit 0
}

if($Approval -ne $RequiredApproval){
    throw "HUMAN GATE RED: Execute requires -Approval $RequiredApproval"
}

New-Item -Path $KeyPath -Force | Out-Null
New-ItemProperty -Path $KeyPath -Name $ValueName -Value $VertexValue -PropertyType String -Force | Out-Null

$after=Read-Reg -Key $KeyPath -Name $ValueName

if(-not $after.value_exists){
    throw 'POST-EXECUTION VERIFY RED: Registry value was not created.'
}

if([string]$after.value -ne $VertexValue){
    throw 'POST-EXECUTION VERIFY RED: Registry value mismatch.'
}

New-Item -ItemType Directory -Path $RegistryRoot -Force | Out-Null

$ledger=$null
if(Test-Path -LiteralPath $LedgerPath -PathType Leaf){
    $ledger=Get-Content -LiteralPath $LedgerPath -Raw -Encoding utf8 | ConvertFrom-Json
}

$records=if($ledger){ @(P $ledger 'records' @()) }else{ @() }

$existingConflict=$records | Where-Object {
    [string](P $_ 'key_path' '') -eq $KeyPath -and
    [string](P $_ 'value_name' '') -eq $ValueName
} | Select-Object -First 1

if($existingConflict){
    throw 'OWNERSHIP RED: Ledger already contains this registry target.'
}

$record=[pscustomobject][ordered]@{
    schema='vertex.registry.ownership-record.v1'
    package_id='vertex.env2.registry-positive.v1'
    key_path=$KeyPath
    value_name=$ValueName
    value_kind='String'
    ownership='VERTEX_CREATED'
    original_exists=$false
    original_value=$null
    vertex_value=$VertexValue
    rollback_eligible=$true
    registered_at=(Get-Date).ToString('o')
}

$records += $record

$newLedger=[ordered]@{
    schema='vertex.registry.ownership-ledger.v1'
    updated_at=(Get-Date).ToString('o')
    records=$records
    notes=@(
        'Registry ownership must be evidence-based.',
        'PRE_EXISTING items are never claimed by Vertex.',
        'Third-party changes block automatic restore/delete.'
    )
}

$newLedger | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $LedgerPath -Encoding utf8

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$receiptPath=Join-Path $ReportRoot "VERTEX_REGISTRY_EXECUTION_RECEIPT.$stamp.json"

$receipt=[ordered]@{
    schema='vertex.registry.execution-receipt.v1'
    package_id='vertex.env2.registry-positive.v1'
    mode='Execute'
    status='EXECUTED_GREEN'
    generated_at=(Get-Date).ToString('o')
    key_path=$KeyPath
    value_name=$ValueName
    before=$before
    after=$after
    ownership='VERTEX_CREATED'
    rollback_eligible=$true
    ledger_path=$LedgerPath
}

$receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receiptPath -Encoding utf8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' REGISTRY POSITIVE OWNERSHIP : GREEN' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ("Ownership         : VERTEX_CREATED")
Write-Host ("Rollback Eligible : True")
Write-Host ("Ledger            : {0}" -f $LedgerPath)
Write-Host ("Receipt           : {0}" -f $receiptPath)
Write-Host '============================================================' -ForegroundColor Green
