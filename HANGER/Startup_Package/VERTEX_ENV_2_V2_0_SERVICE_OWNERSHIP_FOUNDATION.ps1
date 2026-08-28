#requires -Version 7.0
<#
VERTEX ENV-2 V2.0 — WINDOWS SERVICE OWNERSHIP FOUNDATION
READ ONLY / ZERO SERVICE MUTATION

Purpose:
  Inventory Windows services relevant to Vertex/server runtimes.
  Establish evidence schema for future service ownership/restore.
  DO NOT create, modify, start, stop, or delete any service.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$ReportRoot='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$ServiceRoot=Join-Path $ReportRoot '_services'
$LedgerPath=Join-Path $ServiceRoot 'VERTEX_SERVICE_OWNERSHIP_LEDGER.json'
New-Item -ItemType Directory -Path $ServiceRoot -Force | Out-Null

function P {
    param($Object,[string]$Name,$Default=$null)
    if($null -eq $Object){return $Default}
    $p=$Object.PSObject.Properties[$Name]
    if($null -eq $p){return $Default}
    return $p.Value
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.0 — WINDOWS SERVICE OWNERSHIP FOUNDATION' -ForegroundColor Magenta
Write-Host ' INVENTORY -> EVIDENCE -> FUTURE RESTORE ELIGIBILITY' -ForegroundColor Magenta
Write-Host ' READ ONLY / ZERO SERVICE MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$all=@(Get-CimInstance Win32_Service | Sort-Object Name)

$patterns=@(
    'vertex','nginx','caddy','apache','httpd','iis','w3svc','was',
    'postgres','mysql','mariadb','redis','docker','ollama',
    'filemaker','node'
)

$relevant=@(
    $all | Where-Object {
        $hay=("$($_.Name) $($_.DisplayName) $($_.PathName)").ToLowerInvariant()
        foreach($p in $patterns){
            if($hay.Contains($p)){ return $true }
        }
        return $false
    }
)

$inventory=@()
foreach($s in $relevant){
    $inventory += [pscustomobject][ordered]@{
        name=$s.Name
        display_name=$s.DisplayName
        state=$s.State
        start_mode=$s.StartMode
        start_name=$s.StartName
        path_name=$s.PathName
        process_id=$s.ProcessId
        ownership='PRE_EXISTING_NOT_OWNED'
        mutation_allowed=$false
        rollback_eligible=$false
    }
}

if(-not(Test-Path -LiteralPath $LedgerPath -PathType Leaf)){
    $ledger=[ordered]@{
        schema='vertex.service.ownership-ledger.v1'
        updated_at=(Get-Date).ToString('o')
        records=@()
        notes=@(
            'Existing services are never claimed by Vertex.',
            'Future Vertex-created services require before/after evidence.',
            'Service rollback requires ownership proof and live-state verification.'
        )
    }
    $ledger | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $LedgerPath -Encoding utf8
}

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$json=Join-Path $ReportRoot "VERTEX_SERVICE_INVENTORY.$stamp.json"
$txt=Join-Path $ReportRoot "VERTEX_SERVICE_INVENTORY.$stamp.txt"

$report=[ordered]@{
    schema='vertex.service.inventory-report.v1'
    mission='VERTEX_ENV_2_V2_0_SERVICE_OWNERSHIP_FOUNDATION'
    generated_at=(Get-Date).ToString('o')
    mode='READ_ONLY'
    total_services=$all.Count
    relevant_services=$inventory.Count
    services=$inventory
    safety=[ordered]@{
        create='DENIED'
        modify='DENIED'
        start='DENIED'
        stop='DENIED'
        delete='DENIED'
        registry_service_keys='DENIED'
    }
    next_stage='Dedicated Vertex test service positive case — requires explicit human gate and Administrator privileges.'
}

$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $json -Encoding utf8

$lines=@()
$lines += '============================================================'
$lines += ' VERTEX WINDOWS SERVICE INVENTORY'
$lines += '============================================================'
$lines += " Total services      : $($all.Count)"
$lines += " Relevant services   : $($inventory.Count)"
$lines += ''
foreach($s in $inventory){
    $lines += "[PRE_EXISTING_PROTECTED] $($s.name)"
    $lines += "  Display   : $($s.display_name)"
    $lines += "  State     : $($s.state)"
    $lines += "  StartMode : $($s.start_mode)"
    $lines += "  Account   : $($s.start_name)"
    $lines += "  Path      : $($s.path_name)"
}
$lines += ''
$lines += 'SAFETY'
$lines += ' Create / Modify / Start / Stop / Delete : DENIED'
$lines += ' Existing service ownership              : NOT CLAIMED'
$lines += ''
$lines += "JSON : $json"
$lines += "TXT  : $txt"
$lines += '============================================================'

$lines -join [Environment]::NewLine | Set-Content -LiteralPath $txt -Encoding utf8
Write-Host ($lines -join [Environment]::NewLine)

Write-Host ''
Write-Host 'SERVICE OWNERSHIP FOUNDATION : GREEN (READ-ONLY)' -ForegroundColor Green
