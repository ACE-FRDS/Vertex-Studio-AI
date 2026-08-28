#requires -Version 7.0
<#
VERTEX ENV-2 V2.1
DEDICATED TEST SERVICE / OWNERSHIP POSITIVE CASE

DEFAULT: DryRun

Execute:
  - Requires Administrator privileges
  - Creates ONE dedicated VertexEnvTest_* service
  - Does NOT start the service
  - Verifies service existence
  - Registers ownership evidence as VERTEX_CREATED

Safety:
  - Existing services are never modified
  - Service name must begin VertexEnvTest_
  - No Start / Stop / Delete in V2.1
#>

param(
    [ValidateSet('DryRun','Execute')]
    [string]$Mode='DryRun',

    [string]$Approval=''
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$RequiredApproval='APPROVE-SERVICE-TEST'
$ServiceName='VertexEnvTest_20260823_225256'
$DisplayName='Vertex Environment Test Service 20260823_225256'
$BinaryPath="$env:SystemRoot\System32\cmd.exe /c exit 0"

$ReportRoot='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$ServiceRoot=Join-Path $ReportRoot '_services'
$LedgerPath=Join-Path $ServiceRoot 'VERTEX_SERVICE_OWNERSHIP_LEDGER.json'

function P {
    param($Object,[string]$Name,$Default=$null)
    if($null -eq $Object){ return $Default }
    $p=$Object.PSObject.Properties[$Name]
    if($null -eq $p){ return $Default }
    return $p.Value
}

function Is-Administrator {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=[Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Read-ServiceState {
    param([string]$Name)

    $s=Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue

    if(-not $s){
        return [pscustomobject][ordered]@{
            exists=$false
            name=$Name
            display_name=$null
            state=$null
            start_mode=$null
            path_name=$null
            start_name=$null
        }
    }

    return [pscustomobject][ordered]@{
        exists=$true
        name=$s.Name
        display_name=$s.DisplayName
        state=$s.State
        start_mode=$s.StartMode
        path_name=$s.PathName
        start_name=$s.StartName
    }
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.1 — SERVICE OWNERSHIP POSITIVE CASE' -ForegroundColor Magenta
Write-Host ' DEDICATED SERVICE / NO START / HUMAN GATE' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ("Mode        : {0}" -f $Mode)
Write-Host ("Service     : {0}" -f $ServiceName)
Write-Host ("Display     : {0}" -f $DisplayName)
Write-Host ("Binary      : {0}" -f $BinaryPath)

if($ServiceName -notlike 'VertexEnvTest_*'){
    throw 'SAFETY RED: service name is outside VertexEnvTest_* namespace.'
}

$before=Read-ServiceState -Name $ServiceName

Write-Host ''
Write-Host ("Before exists : {0}" -f $before.exists)

if($before.exists){
    throw "POSITIVE CASE RED: dedicated test service already exists: $ServiceName"
}

if($Mode -eq 'DryRun'){
    Write-Host ''
    Write-Host 'DRY RUN GREEN — would create dedicated Vertex test service.' -ForegroundColor Green
    Write-Host 'Service will NOT be started.' -ForegroundColor Green
    exit 0
}

if($Approval -ne $RequiredApproval){
    throw "HUMAN GATE RED: Execute requires -Approval $RequiredApproval"
}

if(-not(Is-Administrator)){
    throw 'ADMINISTRATOR REQUIRED: reopen PowerShell 7 with Run as administrator.'
}

New-Item -ItemType Directory -Path $ServiceRoot -Force | Out-Null

# Create only; do not start.
& "$env:SystemRoot\System32\sc.exe" create $ServiceName `
    binPath= $BinaryPath `
    start= demand `
    DisplayName= $DisplayName | Out-Host

if($LASTEXITCODE -ne 0){
    throw "sc.exe create RED: exit code $LASTEXITCODE"
}

$after=Read-ServiceState -Name $ServiceName

if(-not $after.exists){
    throw 'POST-EXECUTION VERIFY RED: service does not exist after creation.'
}

if($after.name -ne $ServiceName){
    throw 'POST-EXECUTION VERIFY RED: service name mismatch.'
}

if($after.state -eq 'Running'){
    throw 'SAFETY RED: test service unexpectedly entered Running state.'
}

$ledger=$null
if(Test-Path -LiteralPath $LedgerPath -PathType Leaf){
    $ledger=Get-Content -LiteralPath $LedgerPath -Raw -Encoding utf8 | ConvertFrom-Json
}

$records=if($ledger){ @(P $ledger 'records' @()) }else{ @() }

$conflict=$records | Where-Object {
    [string](P $_ 'service_name' '') -eq $ServiceName
} | Select-Object -First 1

if($conflict){
    throw 'OWNERSHIP RED: ledger already contains this service.'
}

$record=[pscustomobject][ordered]@{
    schema='vertex.service.ownership-record.v1'
    package_id='vertex.env2.service-positive.v1'
    service_name=$ServiceName
    display_name=$DisplayName
    ownership='VERTEX_CREATED'
    existed_before=$false
    original_state=$null
    original_start_mode=$null
    original_path_name=$null
    vertex_state=$after.state
    vertex_start_mode=$after.start_mode
    vertex_path_name=$after.path_name
    rollback_eligible=$true
    registered_at=(Get-Date).ToString('o')
}

$records += $record

$newLedger=[ordered]@{
    schema='vertex.service.ownership-ledger.v1'
    updated_at=(Get-Date).ToString('o')
    records=$records
    notes=@(
        'Existing services are never claimed by Vertex.',
        'Vertex-created services require explicit evidence.',
        'V2.1 creates but never starts its dedicated test service.'
    )
}

$newLedger | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $LedgerPath -Encoding utf8

$receiptPath=Join-Path $ReportRoot ("VERTEX_SERVICE_EXECUTION_RECEIPT.{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

$receipt=[ordered]@{
    schema='vertex.service.execution-receipt.v1'
    package_id='vertex.env2.service-positive.v1'
    mode='Execute'
    status='EXECUTED_GREEN'
    generated_at=(Get-Date).ToString('o')
    service_name=$ServiceName
    before=$before
    after=$after
    ownership='VERTEX_CREATED'
    rollback_eligible=$true
    started_by_vertex=$false
    ledger_path=$LedgerPath
}

$receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receiptPath -Encoding utf8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' SERVICE POSITIVE OWNERSHIP : GREEN' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ("Ownership         : VERTEX_CREATED")
Write-Host ("Rollback Eligible : True")
Write-Host ("Service Started   : False")
Write-Host ("Ledger            : {0}" -f $LedgerPath)
Write-Host ("Receipt           : {0}" -f $receiptPath)
Write-Host '============================================================' -ForegroundColor Green
