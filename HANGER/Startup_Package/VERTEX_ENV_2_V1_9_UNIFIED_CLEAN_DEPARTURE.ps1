#requires -Version 7.0
<#
VERTEX ENV-2 V1.9
REGISTRY CLEAN DEPARTURE AUDIT + UNIFIED CLEAN DEPARTURE REPORT

READ ONLY.

Combines:
  - Filesystem ownership / rollback state
  - Registry ownership / rollback state

Important:
  Unified GREEN means GREEN inside IMPLEMENTED SCOPE only.
  Services / Firewall / PATH / Environment are not yet implemented.
#>

param(
    [string]$FilesystemPackageId = '',
    [string]$RegistryPackageId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$FsLedgerPath=Join-Path $ReportRoot '_ownership\VERTEX_PACKAGE_OWNERSHIP_LEDGER.json'
$RegLedgerPath=Join-Path $ReportRoot '_registry\VERTEX_REGISTRY_OWNERSHIP_LEDGER.json'

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

    $r=[ordered]@{key_exists=$false;value_exists=$false;value=$null}
    if(-not(Test-Path -LiteralPath $Key)){ return [pscustomobject]$r }

    $r.key_exists=$true
    $item=Get-Item -LiteralPath $Key -ErrorAction Stop
    $names=@($item.GetValueNames())

    if($names -contains $Name){
        $r.value_exists=$true
        $r.value=$item.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    }

    return [pscustomobject]$r
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V1.9 — UNIFIED CLEAN DEPARTURE AUDIT' -ForegroundColor Magenta
Write-Host ' FILESYSTEM + REGISTRY -> IMPLEMENTED-SCOPE CAMP CLEAN' -ForegroundColor Magenta
Write-Host ' READ ONLY / NO MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

# ------------------------------------------------------------------
# FILESYSTEM AUDIT
# ------------------------------------------------------------------
$fsFindings=@()
$fsRed=0
$fsScanned=0

if(Test-Path -LiteralPath $FsLedgerPath -PathType Leaf){
    $fsLedger=Get-Content -LiteralPath $FsLedgerPath -Raw -Encoding utf8 | ConvertFrom-Json
    $fsRecords=@(P $fsLedger 'records' @())

    if(-not[string]::IsNullOrWhiteSpace($FilesystemPackageId)){
        $fsRecords=@($fsRecords | Where-Object { [string](P $_ 'package_id' '') -eq $FilesystemPackageId })
    }

    foreach($r in $fsRecords){
        $fsScanned++
        $path=N ([string](P $r 'path' ''))
        $ownership=[string](P $r 'ownership' 'UNVERIFIED')
        $exists=if([string]::IsNullOrWhiteSpace($path)){$false}else{Test-Path -LiteralPath $path}
        $status='GREEN'
        $class=''

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

        $fsFindings += [pscustomobject][ordered]@{
            package_id=[string](P $r 'package_id' '')
            path=$path
            ownership=$ownership
            exists_now=$exists
            status=$status
            classification=$class
        }
    }
}

$fsStatus=if($fsRed -eq 0){'FILESYSTEM_CAMP_CLEAN_GREEN'}else{'FILESYSTEM_CAMP_CLEAN_RED'}

# ------------------------------------------------------------------
# REGISTRY AUDIT
# ------------------------------------------------------------------
$regFindings=@()
$regRed=0
$regScanned=0

if(Test-Path -LiteralPath $RegLedgerPath -PathType Leaf){
    $regLedger=Get-Content -LiteralPath $RegLedgerPath -Raw -Encoding utf8 | ConvertFrom-Json
    $regRecords=@(P $regLedger 'records' @())

    if(-not[string]::IsNullOrWhiteSpace($RegistryPackageId)){
        $regRecords=@($regRecords | Where-Object { [string](P $_ 'package_id' '') -eq $RegistryPackageId })
    }

    foreach($r in $regRecords){
        $regScanned++
        $key=[string](P $r 'key_path' '')
        $name=[string](P $r 'value_name' '')
        $ownership=[string](P $r 'ownership' 'UNVERIFIED')
        $live=if([string]::IsNullOrWhiteSpace($key)){
            [pscustomobject]@{key_exists=$false;value_exists=$false;value=$null}
        } else {
            Read-Reg -Key $key -Name $name
        }

        $status='GREEN'
        $class=''

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

        $regFindings += [pscustomobject][ordered]@{
            package_id=[string](P $r 'package_id' '')
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

$implementedScopeGreen=($fsRed -eq 0 -and $regRed -eq 0)
$overall=if($implementedScopeGreen){'UNIFIED_CAMP_CLEAN_GREEN'}else{'UNIFIED_CAMP_CLEAN_RED'}

Write-Host ''
Write-Host ("Filesystem : {0}" -f $fsStatus) -ForegroundColor $(if($fsRed-eq0){'Green'}else{'Red'})
Write-Host ("Registry   : {0}" -f $regStatus) -ForegroundColor $(if($regRed-eq0){'Green'}else{'Red'})

foreach($f in $fsFindings){
    Write-Host ("[FS:{0}] {1}" -f $f.classification,$f.path) -ForegroundColor $(if($f.status-eq'GREEN'){'Green'}else{'Red'})
}

foreach($f in $regFindings){
    Write-Host ("[REG:{0}] {1} -> {2}" -f $f.classification,$f.key_path,$f.value_name) -ForegroundColor $(if($f.status-eq'GREEN'){'Green'}else{'Red'})
}

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$json=Join-Path $ReportRoot "VERTEX_UNIFIED_CLEAN_DEPARTURE_REPORT.$stamp.json"
$txt=Join-Path $ReportRoot "VERTEX_UNIFIED_CLEAN_DEPARTURE_REPORT.$stamp.txt"

$report=[ordered]@{
    schema='vertex.environment.unified-clean-departure-report.v1'
    mission='VERTEX_ENV_2_V1_9_UNIFIED_CLEAN_DEPARTURE'
    generated_at=(Get-Date).ToString('o')
    mode='READ_ONLY_AUDIT'
    status=$overall
    implemented_scope_green=$implementedScopeGreen
    filesystem=[ordered]@{
        status=$fsStatus
        records_scanned=$fsScanned
        red_findings=$fsRed
        findings=$fsFindings
    }
    registry=[ordered]@{
        status=$regStatus
        records_scanned=$regScanned
        red_findings=$regRed
        findings=$regFindings
    }
    not_yet_implemented=[ordered]@{
        services='NOT_IMPLEMENTED'
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
 VERTEX UNIFIED CLEAN DEPARTURE REPORT
============================================================
 Overall                  : $overall

 Filesystem               : $fsStatus
 Filesystem Records       : $fsScanned
 Filesystem Red Findings  : $fsRed

 Registry                 : $regStatus
 Registry Records         : $regScanned
 Registry Red Findings    : $regRed

 IMPLEMENTED SCOPE
  Files / Directories     : AUDITED
  Registry                : AUDITED

 NOT YET IMPLEMENTED
  Services                : NOT IMPLEMENTED
  Firewall                : NOT IMPLEMENTED
  PATH / Environment      : NOT IMPLEMENTED
  Certificates            : NOT IMPLEMENTED
  Scheduled Tasks         : NOT IMPLEMENTED

 JSON                     : $json
 TXT                      : $txt

 $(if($implementedScopeGreen){'UNIFIED CAMP CLEAN : GREEN (IMPLEMENTED SCOPE)'}else{'UNIFIED CAMP CLEAN : RED'})
============================================================
"@

$summary | Set-Content -LiteralPath $txt -Encoding utf8
Write-Host ''
Write-Host $summary -ForegroundColor $(if($implementedScopeGreen){'Green'}else{'Red'})

if(-not $implementedScopeGreen){
    throw 'Unified Clean Departure audit RED.'
}
