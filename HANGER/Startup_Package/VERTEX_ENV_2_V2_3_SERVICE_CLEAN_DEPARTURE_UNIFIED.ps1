#requires -Version 7.0
<#
VERTEX ENV-2 V2.3
SERVICE CLEAN DEPARTURE AUDIT + UNIFIED REPORT EXTENSION

READ ONLY.

Audits:
  - Filesystem ownership ledger
  - Registry ownership ledger
  - Windows Service ownership ledger

Unified GREEN means GREEN inside implemented scope only.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$ReportRoot='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'

$FsLedgerPath=Join-Path $ReportRoot '_ownership\VERTEX_PACKAGE_OWNERSHIP_LEDGER.json'
$RegLedgerPath=Join-Path $ReportRoot '_registry\VERTEX_REGISTRY_OWNERSHIP_LEDGER.json'
$SvcLedgerPath=Join-Path $ReportRoot '_services\VERTEX_SERVICE_OWNERSHIP_LEDGER.json'

function P {
    param($Object,[string]$Name,$Default=$null)
    if($null -eq $Object){ return $Default }
    $p=$Object.PSObject.Properties[$Name]
    if($null -eq $p){ return $Default }
    return $p.Value
}

function N {
    param([string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){ return '' }
    try { return [IO.Path]::GetFullPath($Path).TrimEnd('\') }
    catch { return $Path.TrimEnd('\') }
}

function Read-Reg {
    param([string]$Key,[string]$Name)

    $r=[ordered]@{key_exists=$false;value_exists=$false}
    if(-not(Test-Path -LiteralPath $Key)){ return [pscustomobject]$r }

    $r.key_exists=$true
    $item=Get-Item -LiteralPath $Key -ErrorAction Stop
    $names=@($item.GetValueNames())
    if($names -contains $Name){ $r.value_exists=$true }

    return [pscustomobject]$r
}

function Read-ServiceState {
    param([string]$Name)
    $s=Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if(-not $s){
        return [pscustomobject]@{
            exists=$false
            state=$null
            start_mode=$null
            path_name=$null
        }
    }
    return [pscustomobject]@{
        exists=$true
        state=$s.State
        start_mode=$s.StartMode
        path_name=$s.PathName
    }
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.3 — UNIFIED CLEAN DEPARTURE AUDIT' -ForegroundColor Magenta
Write-Host ' FILESYSTEM + REGISTRY + SERVICES' -ForegroundColor Magenta
Write-Host ' READ ONLY / NO MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

# ------------------------------------------------------------
# Filesystem
# ------------------------------------------------------------
$fsFindings=@(); $fsRed=0; $fsCount=0

if(Test-Path -LiteralPath $FsLedgerPath -PathType Leaf){
    $ledger=Get-Content -LiteralPath $FsLedgerPath -Raw -Encoding utf8 | ConvertFrom-Json
    foreach($r in @(P $ledger 'records' @())){
        $fsCount++
        $path=N ([string](P $r 'path' ''))
        $ownership=[string](P $r 'ownership' 'UNVERIFIED')
        $exists=if([string]::IsNullOrWhiteSpace($path)){$false}else{Test-Path -LiteralPath $path}
        $status='GREEN'; $class=''

        switch($ownership){
            'ROLLED_BACK' {
                if($exists){$status='RED';$class='ROLLBACK_RESIDUE'}else{$class='ROLLBACK_VERIFIED'}
            }
            'PRE_EXISTING_NOT_OWNED' {$class='PRE_EXISTING_PROTECTED'}
            'VERTEX_CREATED' {
                if($exists){$status='RED';$class='VERTEX_LEFTOVER'}else{$class='OWNED_ALREADY_ABSENT'}
            }
            default {$status='RED';$class='UNVERIFIED_OR_CONFLICT'}
        }

        if($status -eq 'RED'){$fsRed++}

        $fsFindings += [pscustomobject]@{
            path=$path
            ownership=$ownership
            exists_now=$exists
            status=$status
            classification=$class
        }
    }
}

$fsStatus=if($fsRed -eq 0){'FILESYSTEM_CAMP_CLEAN_GREEN'}else{'FILESYSTEM_CAMP_CLEAN_RED'}

# ------------------------------------------------------------
# Registry
# ------------------------------------------------------------
$regFindings=@(); $regRed=0; $regCount=0

if(Test-Path -LiteralPath $RegLedgerPath -PathType Leaf){
    $ledger=Get-Content -LiteralPath $RegLedgerPath -Raw -Encoding utf8 | ConvertFrom-Json
    foreach($r in @(P $ledger 'records' @())){
        $regCount++
        $key=[string](P $r 'key_path' '')
        $name=[string](P $r 'value_name' '')
        $ownership=[string](P $r 'ownership' 'UNVERIFIED')
        $live=if([string]::IsNullOrWhiteSpace($key)){[pscustomobject]@{value_exists=$false}}else{Read-Reg $key $name}
        $status='GREEN'; $class=''

        switch($ownership){
            'ROLLED_BACK' {
                if($live.value_exists){$status='RED';$class='REGISTRY_ROLLBACK_RESIDUE'}
                else{$class='REGISTRY_ROLLBACK_VERIFIED'}
            }
            'PRE_EXISTING_NOT_OWNED' {$class='REGISTRY_PRE_EXISTING_PROTECTED'}
            'VERTEX_CREATED' {
                if($live.value_exists){$status='RED';$class='REGISTRY_VERTEX_LEFTOVER'}
                else{$class='REGISTRY_OWNED_ALREADY_ABSENT'}
            }
            default {$status='RED';$class='REGISTRY_UNVERIFIED_OR_CONFLICT'}
        }

        if($status -eq 'RED'){$regRed++}

        $regFindings += [pscustomobject]@{
            key_path=$key
            value_name=$name
            ownership=$ownership
            value_exists_now=$live.value_exists
            status=$status
            classification=$class
        }
    }
}

$regStatus=if($regRed -eq 0){'REGISTRY_CAMP_CLEAN_GREEN'}else{'REGISTRY_CAMP_CLEAN_RED'}

# ------------------------------------------------------------
# Services
# ------------------------------------------------------------
$svcFindings=@(); $svcRed=0; $svcCount=0

if(Test-Path -LiteralPath $SvcLedgerPath -PathType Leaf){
    $ledger=Get-Content -LiteralPath $SvcLedgerPath -Raw -Encoding utf8 | ConvertFrom-Json

    foreach($r in @(P $ledger 'records' @())){
        $svcCount++
        $name=[string](P $r 'service_name' '')
        $ownership=[string](P $r 'ownership' 'UNVERIFIED')
        $live=Read-ServiceState $name
        $status='GREEN'; $class=''

        switch($ownership){
            'ROLLED_BACK' {
                if($live.exists){
                    $status='RED'
                    $class='SERVICE_ROLLBACK_RESIDUE'
                } else {
                    $class='SERVICE_ROLLBACK_VERIFIED'
                }
            }
            'PRE_EXISTING_NOT_OWNED' {
                $class='SERVICE_PRE_EXISTING_PROTECTED'
            }
            'VERTEX_CREATED' {
                if($live.exists){
                    $status='RED'
                    $class='SERVICE_VERTEX_LEFTOVER'
                } else {
                    $class='SERVICE_OWNED_ALREADY_ABSENT'
                }
            }
            default {
                $status='RED'
                $class='SERVICE_UNVERIFIED_OR_CONFLICT'
            }
        }

        if($status -eq 'RED'){$svcRed++}

        $svcFindings += [pscustomobject]@{
            service_name=$name
            ownership=$ownership
            exists_now=$live.exists
            live_state=$live.state
            live_start_mode=$live.start_mode
            live_path_name=$live.path_name
            status=$status
            classification=$class
        }
    }
}

$svcStatus=if($svcRed -eq 0){'SERVICE_CAMP_CLEAN_GREEN'}else{'SERVICE_CAMP_CLEAN_RED'}

# ------------------------------------------------------------
# Unified
# ------------------------------------------------------------
$implementedGreen=($fsRed -eq 0 -and $regRed -eq 0 -and $svcRed -eq 0)
$overall=if($implementedGreen){'UNIFIED_CAMP_CLEAN_GREEN'}else{'UNIFIED_CAMP_CLEAN_RED'}

Write-Host ''
Write-Host ("Filesystem : {0}" -f $fsStatus) -ForegroundColor $(if($fsRed-eq0){'Green'}else{'Red'})
Write-Host ("Registry   : {0}" -f $regStatus) -ForegroundColor $(if($regRed-eq0){'Green'}else{'Red'})
Write-Host ("Services   : {0}" -f $svcStatus) -ForegroundColor $(if($svcRed-eq0){'Green'}else{'Red'})

foreach($f in $fsFindings){
    Write-Host ("[FS:{0}] {1}" -f $f.classification,$f.path) -ForegroundColor $(if($f.status-eq'GREEN'){'Green'}else{'Red'})
}

foreach($f in $regFindings){
    Write-Host ("[REG:{0}] {1} -> {2}" -f $f.classification,$f.key_path,$f.value_name) -ForegroundColor $(if($f.status-eq'GREEN'){'Green'}else{'Red'})
}

foreach($f in $svcFindings){
    Write-Host ("[SVC:{0}] {1}" -f $f.classification,$f.service_name) -ForegroundColor $(if($f.status-eq'GREEN'){'Green'}else{'Red'})
}

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$json=Join-Path $ReportRoot "VERTEX_UNIFIED_CLEAN_DEPARTURE_V2_3.$stamp.json"
$txt=Join-Path $ReportRoot "VERTEX_UNIFIED_CLEAN_DEPARTURE_V2_3.$stamp.txt"

$report=[ordered]@{
    schema='vertex.environment.unified-clean-departure-report.v1.1'
    mission='VERTEX_ENV_2_V2_3_UNIFIED_CLEAN_DEPARTURE'
    generated_at=(Get-Date).ToString('o')
    mode='READ_ONLY_AUDIT'
    status=$overall
    implemented_scope_green=$implementedGreen
    filesystem=[ordered]@{
        status=$fsStatus
        records_scanned=$fsCount
        red_findings=$fsRed
        findings=$fsFindings
    }
    registry=[ordered]@{
        status=$regStatus
        records_scanned=$regCount
        red_findings=$regRed
        findings=$regFindings
    }
    services=[ordered]@{
        status=$svcStatus
        records_scanned=$svcCount
        red_findings=$svcRed
        findings=$svcFindings
    }
    implemented=[ordered]@{
        filesystem='AUDITED'
        registry='AUDITED'
        services='AUDITED'
    }
    not_yet_implemented=[ordered]@{
        firewall='NOT_IMPLEMENTED'
        path_environment='NOT_IMPLEMENTED'
        certificates='NOT_IMPLEMENTED'
        scheduled_tasks='NOT_IMPLEMENTED'
    }
    clean_departure_principle='Vertex removes only what it can prove it owns, and restores only what it can prove it changed.'
}

$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $json -Encoding utf8

$summary=@"
============================================================
 VERTEX UNIFIED CLEAN DEPARTURE REPORT V2.3
============================================================
 Overall                  : $overall

 Filesystem               : $fsStatus
 Filesystem Records       : $fsCount
 Filesystem Red Findings  : $fsRed

 Registry                 : $regStatus
 Registry Records         : $regCount
 Registry Red Findings    : $regRed

 Services                 : $svcStatus
 Service Records          : $svcCount
 Service Red Findings     : $svcRed

 IMPLEMENTED SCOPE
  Files / Directories     : AUDITED
  Registry                : AUDITED
  Services                : AUDITED

 NOT YET IMPLEMENTED
  Firewall                : NOT IMPLEMENTED
  PATH / Environment      : NOT IMPLEMENTED
  Certificates            : NOT IMPLEMENTED
  Scheduled Tasks         : NOT IMPLEMENTED

 JSON                     : $json
 TXT                      : $txt

 $(if($implementedGreen){'UNIFIED CAMP CLEAN : GREEN (IMPLEMENTED SCOPE)'}else{'UNIFIED CAMP CLEAN : RED'})
============================================================
"@

$summary | Set-Content -LiteralPath $txt -Encoding utf8
Write-Host ''
Write-Host $summary -ForegroundColor $(if($implementedGreen){'Green'}else{'Red'})

if(-not $implementedGreen){
    throw 'Unified Clean Departure V2.3 audit RED.'
}
