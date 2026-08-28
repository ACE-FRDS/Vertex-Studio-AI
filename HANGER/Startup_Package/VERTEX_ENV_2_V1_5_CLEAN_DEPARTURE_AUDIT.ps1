#requires -Version 7.0
param([string]$PackageId = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function P {
    param($Object,[string]$Name,$Default=$null)
    if($null -eq $Object){ return $Default }
    $prop=$Object.PSObject.Properties[$Name]
    if($null -eq $prop){ return $Default }
    return $prop.Value
}
function N {
    param([string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){ return '' }
    try { return [IO.Path]::GetFullPath($Path).TrimEnd('\') }
    catch { return $Path.TrimEnd('\') }
}

$ReportRoot='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$LedgerPath=Join-Path $ReportRoot '_ownership\VERTEX_PACKAGE_OWNERSHIP_LEDGER.json'
if(-not(Test-Path -LiteralPath $LedgerPath -PathType Leaf)){ throw "Ownership ledger not found: $LedgerPath" }

$ledger=Get-Content -LiteralPath $LedgerPath -Raw -Encoding utf8 | ConvertFrom-Json
$records=@(P $ledger 'records' @())
if(-not[string]::IsNullOrWhiteSpace($PackageId)){
    $records=@($records | Where-Object { [string](P $_ 'package_id' '') -eq $PackageId })
}
if($records.Count -eq 0){ throw 'No ownership records found for this audit scope.' }

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V1.5 - CLEAN DEPARTURE AUDIT' -ForegroundColor Magenta
Write-Host ' OWNERSHIP LEDGER -> LEFTOVER SCAN -> CAMP CLEAN' -ForegroundColor Magenta
Write-Host ' READ ONLY / NO DELETE' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$findings=@()
$remaining=0;$rolled=0;$pre=0;$conflicts=0;$unverified=0;$absentOwned=0
$i=0

foreach($r in $records){
    $i++
    $pkg=[string](P $r 'package_id' 'UNKNOWN')
    $path=N ([string](P $r 'path' ''))
    $ownership=[string](P $r 'ownership' 'UNVERIFIED')
    $rollback=[bool](P $r 'rollback_eligible' $false)
    $asset=[string](P $r 'asset_type' 'unknown')
    $exists=if([string]::IsNullOrWhiteSpace($path)){$false}else{Test-Path -LiteralPath $path}
    $status='GREEN';$class='';$detail=''

    switch($ownership){
        'VERTEX_CREATED' {
            if($exists){$status='RED';$class='VERTEX_LEFTOVER';$detail='Vertex-owned artifact still exists.';$remaining++}
            else{$class='OWNED_ALREADY_ABSENT';$detail='Vertex-owned artifact is absent.';$absentOwned++}
        }
        'ROLLED_BACK' {
            if($exists){$status='RED';$class='ROLLBACK_RESIDUE';$detail='Ledger says rolled back, but artifact still exists.';$remaining++}
            else{$class='ROLLBACK_VERIFIED';$detail='Rolled-back artifact is physically absent.';$rolled++}
        }
        'PRE_EXISTING_NOT_OWNED' {
            $class='PRE_EXISTING_PROTECTED'
            $detail=if($exists){'Pre-existing asset remains untouched.'}else{'Pre-existing asset is absent; Vertex claims no ownership.'}
            $pre++
        }
        'CONFLICT' {$status='RED';$class='OWNERSHIP_CONFLICT';$detail='Ownership conflict requires human review.';$conflicts++}
        'UNVERIFIED' {$status='RED';$class='OWNERSHIP_UNVERIFIED';$detail='Ownership is not verified.';$unverified++}
        default {$status='RED';$class='UNKNOWN_OWNERSHIP_STATE';$detail="Unsupported state: $ownership";$unverified++}
    }

    $finding=[pscustomobject][ordered]@{
        index=$i;package_id=$pkg;path=$path;asset_type=$asset;ownership=$ownership;
        rollback_eligible=$rollback;exists_now=$exists;status=$status;classification=$class;detail=$detail
    }
    $findings+=$finding
    $color=if($status-eq'GREEN'){'Green'}else{'Red'}
    Write-Host ("[{0}] {1}" -f $class,$path) -ForegroundColor $color
    Write-Host ("    ownership : {0}" -f $ownership)
    Write-Host ("    exists    : {0}" -f $exists)
}

$red=@($findings | Where-Object status -eq 'RED')
$camp=if($red.Count -eq 0 -and $remaining -eq 0){'CAMP_CLEAN_GREEN'}else{'CAMP_CLEAN_RED'}
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$json=Join-Path $ReportRoot "VERTEX_CLEAN_DEPARTURE_REPORT.$stamp.json"
$txt=Join-Path $ReportRoot "VERTEX_CLEAN_DEPARTURE_REPORT.$stamp.txt"

$report=[ordered]@{
    schema='vertex.environment.clean-departure-report.v1'
    mission_id='VERTEX_ENV_2_V1_5_CLEAN_DEPARTURE_AUDIT'
    generated_at=(Get-Date).ToString('o')
    scope_package_id=if([string]::IsNullOrWhiteSpace($PackageId)){$null}else{$PackageId}
    ledger_path=$LedgerPath
    mode='READ_ONLY_AUDIT'
    status=$camp
    summary=[ordered]@{
        records_scanned=$records.Count
        vertex_owned_remaining=$remaining
        rollback_verified=$rolled
        pre_existing_protected=$pre
        owned_already_absent=$absentOwned
        conflicts=$conflicts
        unverified=$unverified
        red_findings=$red.Count
    }
    findings=$findings
    current_scope=[ordered]@{
        filesystem='AUDITED'
        registry='NOT_IMPLEMENTED_YET'
        services='NOT_IMPLEMENTED_YET'
        firewall='NOT_IMPLEMENTED_YET'
        path_environment='NOT_IMPLEMENTED_YET'
    }
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $json -Encoding utf8

$summary=@"
============================================================
 VERTEX CLEAN DEPARTURE REPORT
============================================================
 Status                 : $camp
 Records Scanned        : $($records.Count)
 Vertex-owned Remaining : $remaining
 Rollback Verified      : $rolled
 Pre-existing Protected : $pre
 Owned Already Absent   : $absentOwned
 Conflicts              : $conflicts
 Unverified             : $unverified
 Red Findings           : $($red.Count)

 JSON Report            : $json
 TXT Report             : $txt

 CURRENT V1.5 SCOPE
  Files / Directories   : AUDITED
  Registry              : NOT IMPLEMENTED YET
  Services              : NOT IMPLEMENTED YET
  Firewall              : NOT IMPLEMENTED YET
  PATH / Environment    : NOT IMPLEMENTED YET

 $(if($camp-eq'CAMP_CLEAN_GREEN'){'CAMP CLEAN : GREEN'}else{'CAMP CLEAN : RED'})
============================================================
"@
$summary | Set-Content -LiteralPath $txt -Encoding utf8
Write-Host ''
Write-Host $summary -ForegroundColor $(if($camp-eq'CAMP_CLEAN_GREEN'){'Green'}else{'Red'})
if($camp-ne'CAMP_CLEAN_GREEN'){ throw 'Clean Departure audit RED.' }
