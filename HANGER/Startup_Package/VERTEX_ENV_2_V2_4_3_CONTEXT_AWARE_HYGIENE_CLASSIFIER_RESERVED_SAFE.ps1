#requires -Version 7.0
<#
VERTEX ENV-2 V2.4.2 — CONTEXT-AWARE SECURITY HYGIENE CLASSIFIER
READ ONLY / ZERO MUTATION

Goal:
  Reduce noisy firewall findings by correlating:
    - Windows/system baseline signals
    - Executable existence
    - Installed application hints
    - Windows services
    - Listening ports
    - Firewall rule context

This tool DOES NOT delete or modify anything.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$ReportRoot='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'

function Is-WindowsPath {
    param([string]$Program)
    if([string]::IsNullOrWhiteSpace($Program)){ return $false }
    $p=$Program.ToLowerInvariant()
    return (
        $p.StartsWith(($env:WINDIR.ToLowerInvariant() + '\')) -or
        $p -eq 'system' -or
        $p -eq 'any'
    )
}

function Normalize-PortTokens {
    param([string]$Value)
    if([string]::IsNullOrWhiteSpace($Value)){ return @() }
    return @(
        $Value -split '[,\s]+' |
        Where-Object { $_ -and $_ -ne 'Any' -and $_ -notmatch 'RPC|RPCEPMap|Teredo|IPHTTPS' }
    )
}

function Get-ServiceEvidence {
    param([string]$Program)

    if([string]::IsNullOrWhiteSpace($Program) -or $Program -in @('Any','System')){
        return @()
    }

    $leaf=[IO.Path]::GetFileName($Program)
    if([string]::IsNullOrWhiteSpace($leaf)){ return @() }

    return @(
        Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object {
            ([string]$_.PathName) -match [regex]::Escape($leaf)
        } |
        Select-Object Name,DisplayName,State,StartMode,PathName
    )
}

function Get-InstalledAppHints {
    param([string]$Program)

    if([string]::IsNullOrWhiteSpace($Program) -or $Program -in @('Any','System')){
        return @()
    }

    $exeDir=''
    try { $exeDir=[IO.Path]::GetDirectoryName($Program) } catch {}

    $keys=@(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $apps=@()
    foreach($k in $keys){
        try {
            $apps += Get-ItemProperty $k -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.DisplayName -and (
                        ([string]$_.InstallLocation -and $exeDir -and $exeDir.StartsWith([string]$_.InstallLocation,[System.StringComparison]::OrdinalIgnoreCase)) -or
                        ([string]$_.DisplayIcon -and ([string]$_.DisplayIcon -match [regex]::Escape([IO.Path]::GetFileName($Program))))
                    )
                } |
                Select-Object DisplayName,DisplayVersion,InstallLocation,Publisher
        } catch {}
    }
    return @($apps)
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.4.2 — CONTEXT-AWARE HYGIENE CLASSIFIER' -ForegroundColor Magenta
Write-Host ' FIREWALL + PROGRAM + SERVICE + LISTENER + APP CONTEXT' -ForegroundColor Magenta
Write-Host ' READ ONLY / ZERO MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$rules=@(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop)
$appFilters=@(Get-NetFirewallApplicationFilter -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
$portFilters=@(Get-NetFirewallPortFilter -PolicyStore ActiveStore -ErrorAction SilentlyContinue)

$appById=@{}
foreach($a in $appFilters){ if($a.InstanceID){$appById[[string]$a.InstanceID]=$a} }

$portById=@{}
foreach($p in $portFilters){ if($p.InstanceID){$portById[[string]$p.InstanceID]=$p} }

$listeners=@()
try {
    $listeners += Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Select-Object @{n='Protocol';e={'TCP'}},LocalPort,OwningProcess
} catch {}
try {
    $listeners += Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
        Select-Object @{n='Protocol';e={'UDP'}},LocalPort,OwningProcess
} catch {}

$findings=@()

foreach($r in $rules){
    $a=$appById[[string]$r.InstanceID]
    $p=$portById[[string]$r.InstanceID]

    $program=if($a){[string]$a.Program}else{''}
    $protocol=if($p){[string]$p.Protocol}else{''}
    $localPort=if($p){[string]$p.LocalPort}else{''}

    $programExists=$null
    $programKind='UNKNOWN'

    if([string]::IsNullOrWhiteSpace($program) -or $program -eq 'Any'){
        $programKind='ANY'
    }
    elseif($program -eq 'System'){
        $programKind='SYSTEM'
        $programExists=$true
    }
    elseif($program -match '^[A-Za-z]:\\'){
        $programKind='FILE'
        $programExists=Test-Path -LiteralPath $program -PathType Leaf
    }
    else{
        $programKind='SPECIAL'
    }

    $isWindowsPath=Is-WindowsPath $program
    $services=@(Get-ServiceEvidence $program)
    $apps=@(Get-InstalledAppHints $program)

    $ports=Normalize-PortTokens $localPort
    $listenerMatch=$false

    foreach($pt in $ports){
        if($pt -match '^\d+$'){
            if($listeners | Where-Object { $_.Protocol -eq $protocol -and $_.LocalPort -eq [int]$pt }){
                $listenerMatch=$true
                break
            }
        }
    }

    $classification='IGNORE'
    $risk='INFO'
    $reasons=[System.Collections.Generic.List[string]]::new()

    if($programKind -eq 'FILE' -and $programExists -eq $false){
        if($isWindowsPath){
            $classification='SYSTEM_COMPONENT_MISSING_REVIEW'
            $risk='LOW'
            $reasons.Add('WINDOWS_PATH_BUT_BINARY_MISSING')
        } else {
            if($services.Count -eq 0 -and $apps.Count -eq 0){
                $classification='ORPHAN_CONFIRMED_CANDIDATE'
                $risk='HIGH'
                $reasons.Add('BINARY_MISSING')
                $reasons.Add('NO_SERVICE_EVIDENCE')
                $reasons.Add('NO_INSTALLED_APP_EVIDENCE')
            } else {
                $classification='STALE_APPLICATION_ARTIFACT'
                $risk='MEDIUM'
                $reasons.Add('BINARY_MISSING_BUT_RELATED_EVIDENCE_EXISTS')
            }
        }
    }
    elseif($r.Direction -eq 'Inbound' -and $r.Action -eq 'Allow'){
        if($isWindowsPath){
            $classification='SYSTEM_BASELINE_REVIEW'
            $risk='LOW'
            $reasons.Add('WINDOWS_OR_SYSTEM_RULE')
        }
        elseif($programKind -eq 'ANY'){
            $classification='BROAD_RULE_REVIEW'
            $risk='MEDIUM'
            $reasons.Add('PROGRAM_ANY')
        }
        else{
            $classification='ACTIVE_APPLICATION_RULE'
            $risk='INFO'
            $reasons.Add('PROGRAM_PRESENT')
        }

        if(([string]$r.Profile) -match '(?i)Public|Any'){
            $reasons.Add('PUBLIC_OR_ANY_PROFILE')
            if($risk -eq 'INFO'){ $risk='LOW' }
        }

        if($listenerMatch){
            $reasons.Add('LISTENER_PRESENT')
        }
        elseif($ports.Count -gt 0){
            $reasons.Add('NO_MATCHING_LISTENER_OBSERVED')
        }
    }

    if($classification -eq 'IGNORE'){ continue }

    $findings += [pscustomobject][ordered]@{
        display_name=[string]$r.DisplayName
        name=[string]$r.Name
        policy_store_source=[string]$r.PolicyStoreSource
        direction=[string]$r.Direction
        action=[string]$r.Action
        enabled=[string]$r.Enabled
        profile=[string]$r.Profile
        program=$program
        program_kind=$programKind
        program_exists=$programExists
        is_windows_baseline=$isWindowsPath
        service_evidence=@($services)
        installed_app_evidence=@($apps)
        protocol=$protocol
        local_port=$localPort
        listener_match=$listenerMatch
        classification=$classification
        risk=$risk
        reasons=@($reasons)
        automatic_cleanup='DENIED'
    }
}

$priority=@(
    $findings |
    Where-Object { $_.classification -in @('ORPHAN_CONFIRMED_CANDIDATE','STALE_APPLICATION_ARTIFACT','BROAD_RULE_REVIEW') }
)

$system=@($findings | Where-Object { $_.classification -like 'SYSTEM_*' })
$active=@($findings | Where-Object { $_.classification -eq 'ACTIVE_APPLICATION_RULE' })

Write-Host ''
Write-Host "Total firewall rules              : $($rules.Count)"
Write-Host "Priority human-review findings    : $($priority.Count)" -ForegroundColor Yellow
Write-Host "System baseline/review findings   : $($system.Count)"
Write-Host "Active application rules          : $($active.Count)"
Write-Host ''

foreach($f in $priority){
    $color=if($f.risk -eq 'HIGH'){'Red'}elseif($f.risk -eq 'MEDIUM'){'Yellow'}else{'Cyan'}
    Write-Host "[$($f.classification)] $($f.display_name)" -ForegroundColor $color
    Write-Host "  Risk        : $($f.risk)"
    Write-Host "  Program     : $($f.program)"
    Write-Host "  Exists      : $($f.program_exists)"
    Write-Host "  Services    : $(@($f.service_evidence).Count)"
    Write-Host "  Apps        : $(@($f.installed_app_evidence).Count)"
    Write-Host "  Listener    : $($f.listener_match)"
    Write-Host "  Profile     : $($f.profile)"
    Write-Host "  LocalPort   : $($f.local_port)"
    Write-Host "  Reasons     : $($f.reasons -join ', ')"
}

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$json=Join-Path $ReportRoot "VERTEX_SECURITY_HYGIENE_CONTEXT.$stamp.json"
$txt=Join-Path $ReportRoot "VERTEX_SECURITY_HYGIENE_CONTEXT.$stamp.txt"

$report=[ordered]@{
    schema='vertex.environment.security-hygiene.context.v1'
    mission='VERTEX_ENV_2_V2_4_2_CONTEXT_AWARE_CLASSIFIER'
    generated_at=(Get-Date).ToString('o')
    mode='READ_ONLY'
    total_rules=$rules.Count
    priority_review=$priority.Count
    system_review=$system.Count
    active_application_rules=$active.Count
    findings=$findings
    policy=[ordered]@{
        mutation='NONE'
        automatic_cleanup='DENIED'
        human_gate='REQUIRED'
        principle='Reduce noise before asking a human to decide.'
    }
}

$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $json -Encoding utf8

@"
============================================================
 VERTEX CONTEXT-AWARE SECURITY HYGIENE REPORT
============================================================
 Total Rules             : $($rules.Count)
 Priority Review         : $($priority.Count)
 System Review           : $($system.Count)
 Active Application      : $($active.Count)

 Automatic Cleanup       : DENIED
 Human Gate              : REQUIRED
 Mutation                : NONE

 JSON                    : $json
 TXT                     : $txt
============================================================
"@ | Set-Content -LiteralPath $txt -Encoding utf8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' CONTEXT-AWARE CLASSIFICATION COMPLETE' -ForegroundColor Green
Write-Host " Priority Review : $($priority.Count)"
Write-Host " JSON            : $json"
Write-Host " TXT             : $txt"
Write-Host ' ZERO MUTATION' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
