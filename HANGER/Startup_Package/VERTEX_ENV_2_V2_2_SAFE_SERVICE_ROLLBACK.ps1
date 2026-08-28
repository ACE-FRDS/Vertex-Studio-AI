#requires -Version 7.0
<#
VERTEX ENV-2 V2.2 — SAFE SERVICE ROLLBACK

DEFAULT: DryRun

Eligible:
  ownership == VERTEX_CREATED
  rollback_eligible == true
  service_name starts with VertexEnvTest_
  live PathName matches ledger vertex_path_name
  live StartMode matches ledger vertex_start_mode
  service is NOT Running

Denied:
  existing/pre-existing services
  running services
  config drift
  service name outside VertexEnvTest_*
  any unverified/conflict state

Execute:
  sc.exe delete
  verify service no longer exists
  ledger -> ROLLED_BACK
#>

param(
    [ValidateSet('DryRun','Execute')]
    [string]$Mode='DryRun',

    [string]$Approval='',

    [string]$PackageId='vertex.env2.service-positive.v1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$RequiredApproval='APPROVE-SERVICE-ROLLBACK'
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

function Normalize-String {
    param($Value)
    if($null -eq $Value){ return '' }
    return ([string]$Value).Trim()
}

if(-not(Test-Path -LiteralPath $LedgerPath -PathType Leaf)){
    throw "Service ownership ledger not found: $LedgerPath"
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
Write-Host ' VERTEX ENV-2 V2.2 — SAFE SERVICE ROLLBACK' -ForegroundColor Magenta
Write-Host ' OWNERSHIP -> LIVE CONFIG MATCH -> HUMAN GATE -> DELETE' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ("Mode      : {0}" -f $Mode)
Write-Host ("Package   : {0}" -f $PackageId)
Write-Host ("Targets   : {0}" -f $targets.Count)

if($targets.Count -eq 0){
    throw "No rollback-eligible service assets for package: $PackageId"
}

if($Mode -eq 'Execute'){
    if($Approval -ne $RequiredApproval){
        throw "HUMAN GATE RED: Execute requires -Approval $RequiredApproval"
    }

    if(-not(Is-Administrator)){
        throw 'ADMINISTRATOR REQUIRED: reopen PowerShell 7 with Run as administrator.'
    }
}

$results=@()
$index=0

foreach($record in $targets){
    $index++

    $name=[string](P $record 'service_name' '')
    $ledgerPathName=Normalize-String (P $record 'vertex_path_name' '')
    $ledgerStartMode=Normalize-String (P $record 'vertex_start_mode' '')
    $live=Read-ServiceState -Name $name

    $result=[ordered]@{
        index=$index
        service_name=$name
        status='PENDING'
        action='NONE'
        reason=$null
        existed_before=$live.exists
        live_state=$live.state
        live_start_mode=$live.start_mode
        live_path_name=$live.path_name
        removed=$false
    }

    Write-Host ''
    Write-Host ("[{0}/{1}] {2}" -f $index,$targets.Count,$name) -ForegroundColor Yellow

    if($name -notlike 'VertexEnvTest_*'){
        $result.status='RED'
        $result.action='DENY'
        $result.reason='Service name is outside VertexEnvTest_* namespace.'
        Write-Host '  RED — NAMESPACE DENIED' -ForegroundColor Red
        $results += [pscustomobject]$result
        continue
    }

    if(-not $live.exists){
        $result.status='ALREADY_ABSENT'
        $result.action='NONE'
        $result.reason='Service is already absent.'
        Write-Host '  ALREADY_ABSENT' -ForegroundColor DarkYellow
        $results += [pscustomobject]$result
        continue
    }

    if($live.state -eq 'Running'){
        $result.status='RED'
        $result.action='DENY'
        $result.reason='Service is running; V2.2 will not auto-stop.'
        Write-Host '  RED — RUNNING SERVICE' -ForegroundColor Red
        $results += [pscustomobject]$result
        continue
    }

    if((Normalize-String $live.path_name) -ne $ledgerPathName){
        $result.status='RED'
        $result.action='DENY'
        $result.reason='Live PathName differs from Vertex ownership evidence.'
        Write-Host '  RED — PATH DRIFT' -ForegroundColor Red
        $results += [pscustomobject]$result
        continue
    }

    if((Normalize-String $live.start_mode) -ne $ledgerStartMode){
        $result.status='RED'
        $result.action='DENY'
        $result.reason='Live StartMode differs from Vertex ownership evidence.'
        Write-Host '  RED — START MODE DRIFT' -ForegroundColor Red
        $results += [pscustomobject]$result
        continue
    }

    $result.action='DELETE_VERTEX_CREATED_SERVICE'

    if($Mode -eq 'DryRun'){
        $result.status='DRY_RUN'
        Write-Host '  DRY_RUN — DELETE_VERTEX_CREATED_SERVICE' -ForegroundColor Green
        $results += [pscustomobject]$result
        continue
    }

    & "$env:SystemRoot\System32\sc.exe" delete $name | Out-Host

    if($LASTEXITCODE -ne 0){
        throw "sc.exe delete RED: exit code $LASTEXITCODE"
    }

    Start-Sleep -Milliseconds 500
    $after=Read-ServiceState -Name $name

    if($after.exists){
        throw "POST-ROLLBACK VERIFY RED: service still exists: $name"
    }

    $result.status='ROLLED_BACK'
    $result.removed=$true
    Write-Host '  ROLLED_BACK' -ForegroundColor Green

    $results += [pscustomobject]$result
}

$red=@($results | Where-Object status -eq 'RED')

if($red.Count -gt 0){
    throw "SERVICE ROLLBACK RED: $($red.Count) target(s) denied."
}

if($Mode -eq 'Execute'){
    $updated=@()

    foreach($record in $records){
        $name=[string](P $record 'service_name' '')
        $match=$results | Where-Object { $_.service_name -eq $name } | Select-Object -First 1

        if($match -and $match.status -in @('ROLLED_BACK','ALREADY_ABSENT')){
            $record.ownership='ROLLED_BACK'
            $record.rollback_eligible=$false
            $record | Add-Member -NotePropertyName rolled_back_at -NotePropertyValue (Get-Date).ToString('o') -Force
            $record | Add-Member -NotePropertyName rollback_status -NotePropertyValue $match.status -Force
        }

        $updated += $record
    }

    $newLedger=[ordered]@{
        schema=[string](P $ledger 'schema' 'vertex.service.ownership-ledger.v1')
        updated_at=(Get-Date).ToString('o')
        records=$updated
        notes=@(
            'Existing services are never claimed by Vertex.',
            'Vertex-created services may be deleted only while live configuration matches ownership evidence.',
            'V2.2 does not auto-stop running services.'
        )
    }

    $newLedger | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $LedgerPath -Encoding utf8
}

$receiptPath=Join-Path $ReportRoot ("VERTEX_SERVICE_ROLLBACK_RECEIPT.{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

$receipt=[ordered]@{
    schema='vertex.service.rollback-receipt.v1'
    package_id=$PackageId
    mode=$Mode
    status=if($Mode -eq 'Execute'){'ROLLBACK_GREEN'}else{'DRY_RUN_GREEN'}
    generated_at=(Get-Date).ToString('o')
    approval_verified=($Mode -eq 'Execute' -and $Approval -eq $RequiredApproval)
    ledger_path=$LedgerPath
    results=$results
    safety=[ordered]@{
        pre_existing='DENIED'
        running_service='DENIED'
        config_drift='DENIED'
        outside_vertex_test_namespace='DENIED'
        auto_stop='DENIED'
    }
}

$receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receiptPath -Encoding utf8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' VERTEX SERVICE SAFE ROLLBACK RESULT' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ("Status    : {0}" -f $receipt.status)
Write-Host ("Receipt   : {0}" -f $receiptPath)
Write-Host ("Ledger    : {0}" -f $LedgerPath)
Write-Host '============================================================' -ForegroundColor Green
