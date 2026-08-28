#requires -Version 7.0
<#
VERTEX ENV-2 V1.6 — REGISTRY OWNERSHIP & RESTORE FOUNDATION

V1.6 is deliberately READ-ONLY.
It inventories Registry ownership evidence and produces a restoration plan.
It DOES NOT create, modify, restore, or delete registry keys/values.

Clean Departure rules:
  1. PRE_EXISTING_NOT_OWNED -> never touch.
  2. VERTEX_CREATED -> removable only when current state still matches Vertex evidence.
  3. VERTEX_MODIFIED -> restorable only when current value still matches Vertex-applied value.
  4. THIRD_PARTY_CHANGED -> DENY automatic restore/delete.
  5. UNVERIFIED / CONFLICT -> DENY.
#>

param(
    [string]$EvidencePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$RegistryRoot = Join-Path $ReportRoot '_registry'
$DefaultEvidence = Join-Path $RegistryRoot 'VERTEX_REGISTRY_OWNERSHIP_LEDGER.json'

function Get-Prop {
    param($Object,[string]$Name,$Default=$null)
    if($null -eq $Object){ return $Default }
    $p=$Object.PSObject.Properties[$Name]
    if($null -eq $p){ return $Default }
    return $p.Value
}

function Canonical-RegistryPath {
    param([string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){ return '' }
    $p=$Path.Trim()
    $p=$p -replace '^HKEY_CURRENT_USER\\','HKCU:\'
    $p=$p -replace '^HKEY_LOCAL_MACHINE\\','HKLM:\'
    $p=$p -replace '^HKCU\\','HKCU:\'
    $p=$p -replace '^HKLM\\','HKLM:\'
    return $p
}

function Read-RegistryValue {
    param([string]$KeyPath,[string]$ValueName)

    $result=[ordered]@{
        key_exists=$false
        value_exists=$false
        value=$null
        kind=$null
        readable=$true
        error=$null
    }

    try {
        if(-not(Test-Path -LiteralPath $KeyPath)){
            return [pscustomobject]$result
        }

        $result.key_exists=$true

        if([string]::IsNullOrWhiteSpace($ValueName) -or $ValueName -eq '(Default)'){
            $ValueName=''
        }

        $key=Get-Item -LiteralPath $KeyPath -ErrorAction Stop
        $names=@($key.GetValueNames())

        if($names -contains $ValueName){
            $result.value_exists=$true
            $result.value=$key.GetValue($ValueName,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $result.kind=[string]$key.GetValueKind($ValueName)
        }
    }
    catch {
        $result.readable=$false
        $result.error=$_.Exception.Message
    }

    return [pscustomobject]$result
}

function Values-Equal {
    param($A,$B)

    if($null -eq $A -and $null -eq $B){ return $true }
    if($null -eq $A -or $null -eq $B){ return $false }

    if($A -is [array] -or $B -is [array]){
        return ((@($A) | ConvertTo-Json -Compress) -eq (@($B) | ConvertTo-Json -Compress))
    }

    return ([string]$A -ceq [string]$B)
}

New-Item -ItemType Directory -Path $RegistryRoot -Force | Out-Null

if([string]::IsNullOrWhiteSpace($EvidencePath)){
    $EvidencePath=$DefaultEvidence
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V1.6 — REGISTRY OWNERSHIP FOUNDATION' -ForegroundColor Magenta
Write-Host ' EVIDENCE -> LIVE STATE -> RESTORE ELIGIBILITY' -ForegroundColor Magenta
Write-Host ' READ ONLY / ZERO REGISTRY MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ("Evidence : {0}" -f $EvidencePath)

if(-not(Test-Path -LiteralPath $EvidencePath -PathType Leaf)){
    $template=[ordered]@{
        schema='vertex.registry.ownership-ledger.v1'
        records=@()
        notes=@(
            'V1.6 does not mutate Registry.',
            'Future ENV-2 registry operations must write BEFORE and AFTER evidence here.',
            'Do not manually claim ownership of pre-existing registry data.'
        )
    }

    $template | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding utf8

    Write-Host ''
    Write-Host 'No registry ownership evidence existed.' -ForegroundColor Yellow
    Write-Host 'Created EMPTY LEDGER TEMPLATE ONLY (report-area file; Registry untouched).' -ForegroundColor Yellow
    Write-Host ("Ledger   : {0}" -f $EvidencePath)
    Write-Host ''
    Write-Host 'REGISTRY CAMP CLEAN : UNKNOWN / NO OWNERSHIP EVIDENCE' -ForegroundColor Yellow
    Write-Host '============================================================' -ForegroundColor Magenta
    exit 0
}

$ledger=Get-Content -LiteralPath $EvidencePath -Raw -Encoding utf8 | ConvertFrom-Json
$records=@(Get-Prop $ledger 'records' @())

if($records.Count -eq 0){
    Write-Host ''
    Write-Host 'Registry ownership records : 0' -ForegroundColor Green
    Write-Host 'No Vertex-owned Registry mutations are recorded.' -ForegroundColor Green
    Write-Host 'REGISTRY CAMP CLEAN : GREEN (NO RECORDED MUTATIONS)' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Magenta
    exit 0
}

$findings=@()
$eligible=0
$protected=0
$denied=0
$missing=0

$i=0
foreach($r in $records){
    $i++

    $keyPath=Canonical-RegistryPath ([string](Get-Prop $r 'key_path' ''))
    $valueName=[string](Get-Prop $r 'value_name' '')
    $ownership=[string](Get-Prop $r 'ownership' 'UNVERIFIED')
    $originalExists=[bool](Get-Prop $r 'original_exists' $false)
    $originalValue=Get-Prop $r 'original_value' $null
    $vertexValue=Get-Prop $r 'vertex_value' $null

    if([string]::IsNullOrWhiteSpace($keyPath)){
        $live=[pscustomobject]@{key_exists=$false;value_exists=$false;value=$null;kind=$null;readable=$false;error='Missing key_path'}
    } else {
        $live=Read-RegistryValue -KeyPath $keyPath -ValueName $valueName
    }

    $state='UNVERIFIED'
    $action='DENY'
    $status='RED'
    $reason='Ownership/state cannot be verified.'

    if(-not $live.readable){
        $state='UNREADABLE'
        $reason=$live.error
        $denied++
    }
    elseif($ownership -eq 'PRE_EXISTING_NOT_OWNED'){
        $state='PRE_EXISTING_PROTECTED'
        $action='NONE'
        $status='GREEN'
        $reason='Vertex does not own this registry item.'
        $protected++
    }
    elseif($ownership -eq 'VERTEX_CREATED'){
        if(-not $live.value_exists){
            $state='ALREADY_ABSENT'
            $action='NONE'
            $status='GREEN'
            $reason='Vertex-created value is already absent.'
            $missing++
        }
        elseif(Values-Equal $live.value $vertexValue){
            $state='VERTEX_VALUE_UNCHANGED'
            $action='DELETE_VALUE_ELIGIBLE_FUTURE'
            $status='GREEN'
            $reason='Current value still matches Vertex-created evidence.'
            $eligible++
        }
        else{
            $state='THIRD_PARTY_CHANGED'
            $action='DENY'
            $status='RED'
            $reason='Current value differs from Vertex evidence; automatic deletion denied.'
            $denied++
        }
    }
    elseif($ownership -eq 'VERTEX_MODIFIED'){
        if(-not $live.value_exists){
            $state='VALUE_REMOVED_AFTER_VERTEX'
            $action='DENY'
            $status='RED'
            $reason='Value disappeared after Vertex modification; automatic restore denied.'
            $denied++
        }
        elseif(Values-Equal $live.value $vertexValue){
            $state='VERTEX_VALUE_UNCHANGED'
            $action=if($originalExists){'RESTORE_ORIGINAL_ELIGIBLE_FUTURE'}else{'DELETE_VALUE_ELIGIBLE_FUTURE'}
            $status='GREEN'
            $reason='Current value still matches Vertex-applied value.'
            $eligible++
        }
        else{
            $state='THIRD_PARTY_CHANGED'
            $action='DENY'
            $status='RED'
            $reason='Someone changed the value after Vertex; automatic restore denied.'
            $denied++
        }
    }
    else{
        $state='OWNERSHIP_UNVERIFIED'
        $action='DENY'
        $status='RED'
        $reason="Unsupported or unverified ownership state: $ownership"
        $denied++
    }

    $f=[pscustomobject][ordered]@{
        index=$i
        key_path=$keyPath
        value_name=$valueName
        ownership=$ownership
        original_exists=$originalExists
        original_value=$originalValue
        vertex_value=$vertexValue
        live_key_exists=$live.key_exists
        live_value_exists=$live.value_exists
        live_value=$live.value
        live_kind=$live.kind
        state=$state
        future_action=$action
        status=$status
        reason=$reason
    }
    $findings+=$f

    $color=if($status -eq 'GREEN'){'Green'}else{'Red'}
    Write-Host ''
    Write-Host ("[{0}] {1} -> {2}" -f $state,$keyPath,$valueName) -ForegroundColor $color
    Write-Host ("    ownership     : {0}" -f $ownership)
    Write-Host ("    future action : {0}" -f $action)
    Write-Host ("    reason        : {0}" -f $reason)
}

$red=@($findings | Where-Object status -eq 'RED')
$overall=if($red.Count -eq 0){'REGISTRY_OWNERSHIP_GREEN'}else{'REGISTRY_OWNERSHIP_RED'}

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$json=Join-Path $ReportRoot "VERTEX_REGISTRY_OWNERSHIP_AUDIT.$stamp.json"
$txt=Join-Path $ReportRoot "VERTEX_REGISTRY_OWNERSHIP_AUDIT.$stamp.txt"

$report=[ordered]@{
    schema='vertex.registry.ownership-audit.v1'
    mission='VERTEX_ENV_2_V1_6_REGISTRY_OWNERSHIP'
    generated_at=(Get-Date).ToString('o')
    mode='READ_ONLY'
    status=$overall
    evidence_path=$EvidencePath
    summary=[ordered]@{
        records=$records.Count
        future_restore_or_delete_eligible=$eligible
        pre_existing_protected=$protected
        already_absent=$missing
        denied=$denied
        red_findings=$red.Count
    }
    findings=$findings
    safety=[ordered]@{
        registry_create='DENIED'
        registry_modify='DENIED'
        registry_delete='DENIED'
        restore_execution='NOT_IMPLEMENTED_IN_V1_6'
        third_party_changed='AUTO_RESTORE_DENIED'
    }
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $json -Encoding utf8

$summary=@"
============================================================
 VERTEX REGISTRY OWNERSHIP AUDIT
============================================================
 Status                    : $overall
 Records                   : $($records.Count)
 Future Eligible           : $eligible
 Pre-existing Protected    : $protected
 Already Absent            : $missing
 Denied                    : $denied
 Red Findings              : $($red.Count)

 JSON                      : $json
 TXT                       : $txt

 SAFETY
  Registry Create          : DENIED
  Registry Modify          : DENIED
  Registry Delete          : DENIED
  Restore Execution        : NOT IMPLEMENTED IN V1.6
  Third-party Changed      : AUTO RESTORE DENIED
============================================================
"@
$summary | Set-Content -LiteralPath $txt -Encoding utf8
Write-Host ''
Write-Host $summary -ForegroundColor $(if($overall -eq 'REGISTRY_OWNERSHIP_GREEN'){'Green'}else{'Red'})
