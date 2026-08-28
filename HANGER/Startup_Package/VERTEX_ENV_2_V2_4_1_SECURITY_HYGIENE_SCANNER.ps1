#requires -Version 7.0
<#
VERTEX ENV-2 V2.4.1 — ENVIRONMENT SECURITY HYGIENE SCANNER
READ ONLY / ZERO MUTATION

Correlates firewall rules with executable existence and selected exposure signals.
It does NOT decide that a finding is a vulnerability. It produces evidence-backed
review classifications for the next Vertex planning layer.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.4.1 — SECURITY HYGIENE SCANNER' -ForegroundColor Magenta
Write-Host ' FIREWALL -> PROGRAM -> PORT -> EXPOSURE -> STALE SIGNALS' -ForegroundColor Magenta
Write-Host ' READ ONLY / ZERO MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$rules = @(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop)
$appFilters = @(Get-NetFirewallApplicationFilter -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
$portFilters = @(Get-NetFirewallPortFilter -PolicyStore ActiveStore -ErrorAction SilentlyContinue)

$appByInstance = @{}
foreach($a in $appFilters){ if($a.InstanceID){ $appByInstance[[string]$a.InstanceID] = $a } }

$portByInstance = @{}
foreach($p in $portFilters){ if($p.InstanceID){ $portByInstance[[string]$p.InstanceID] = $p } }

$findings = @()

foreach($r in $rules){
    $a = $appByInstance[[string]$r.InstanceID]
    $p = $portByInstance[[string]$r.InstanceID]

    $program = if($a){ [string]$a.Program } else { '' }
    $protocol = if($p){ [string]$p.Protocol } else { '' }
    $localPort = if($p){ [string]$p.LocalPort } else { '' }

    $programKind = 'UNKNOWN'
    $programExists = $null

    if([string]::IsNullOrWhiteSpace($program) -or $program -eq 'Any'){
        $programKind = 'ANY'
    }
    elseif($program -eq 'System'){
        $programKind = 'SYSTEM'
        $programExists = $true
    }
    elseif($program -match '^[A-Za-z]:\\'){
        $programKind = 'FILE'
        $programExists = Test-Path -LiteralPath $program -PathType Leaf
    }
    else {
        $programKind = 'SPECIAL'
    }

    $signals = [System.Collections.Generic.List[string]]::new()
    $severity = 'INFO'

    if($r.Direction -eq 'Inbound' -and $r.Action -eq 'Allow' -and $r.Enabled -eq 'True'){
        $signals.Add('INBOUND_ALLOW_ENABLED')
    }

    if($programKind -eq 'FILE' -and $programExists -eq $false){
        $signals.Add('PROGRAM_MISSING')
        $severity = 'REVIEW'
    }

    if($programKind -eq 'ANY' -and $r.Direction -eq 'Inbound' -and $r.Action -eq 'Allow'){
        $signals.Add('PROGRAM_ANY_INBOUND_ALLOW')
        $severity = 'REVIEW'
    }

    $profileText = [string]$r.Profile
    if($profileText -match '(?i)Public|Any'){
        if($r.Direction -eq 'Inbound' -and $r.Action -eq 'Allow'){
            $signals.Add('PUBLIC_OR_ANY_PROFILE_EXPOSURE')
            if($severity -eq 'INFO'){ $severity = 'REVIEW' }
        }
    }

    if($signals.Count -eq 0){ continue }

    $classification = if($signals -contains 'PROGRAM_MISSING'){
        'ORPHAN_FIREWALL_CANDIDATE'
    }
    elseif($signals -contains 'PROGRAM_ANY_INBOUND_ALLOW'){
        'BROAD_RULE_REVIEW'
    }
    else {
        'ACTIVE_RULE_REVIEW'
    }

    $findings += [pscustomobject][ordered]@{
        display_name = [string]$r.DisplayName
        name = [string]$r.Name
        policy_store_source = [string]$r.PolicyStoreSource
        direction = [string]$r.Direction
        action = [string]$r.Action
        enabled = [string]$r.Enabled
        profile = $profileText
        program = $program
        program_kind = $programKind
        program_exists = $programExists
        protocol = $protocol
        local_port = $localPort
        classification = $classification
        severity = $severity
        signals = @($signals)
        automatic_cleanup = 'DENIED'
    }
}

$orphans = @($findings | Where-Object classification -eq 'ORPHAN_FIREWALL_CANDIDATE')
$broad = @($findings | Where-Object classification -eq 'BROAD_RULE_REVIEW')
$review = @($findings | Where-Object severity -eq 'REVIEW')

Write-Host ''
Write-Host "Total firewall rules       : $($rules.Count)"
Write-Host "Review findings            : $($review.Count)"
Write-Host "Orphan candidates          : $($orphans.Count)" -ForegroundColor $(if($orphans.Count){'Yellow'}else{'Green'})
Write-Host "Broad-rule review          : $($broad.Count)" -ForegroundColor $(if($broad.Count){'Yellow'}else{'Green'})
Write-Host ''

foreach($f in $review){
    $c = if($f.classification -eq 'ORPHAN_FIREWALL_CANDIDATE'){'Yellow'}else{'Cyan'}
    Write-Host "[$($f.classification)] $($f.display_name)" -ForegroundColor $c
    Write-Host "  Program      : $($f.program)"
    Write-Host "  Exists       : $($f.program_exists)"
    Write-Host "  Direction    : $($f.direction)"
    Write-Host "  Profile      : $($f.profile)"
    Write-Host "  Protocol     : $($f.protocol)"
    Write-Host "  LocalPort    : $($f.local_port)"
    Write-Host "  PolicyStore  : $($f.policy_store_source)"
    Write-Host "  Signals      : $($f.signals -join ', ')"
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $ReportRoot "VERTEX_SECURITY_HYGIENE_FIREWALL.$stamp.json"
$txt = Join-Path $ReportRoot "VERTEX_SECURITY_HYGIENE_FIREWALL.$stamp.txt"

$report = [ordered]@{
    schema='vertex.environment.security-hygiene.firewall.v1'
    mission='VERTEX_ENV_2_V2_4_1_SECURITY_HYGIENE_SCANNER'
    generated_at=(Get-Date).ToString('o')
    mode='READ_ONLY'
    total_firewall_rules=$rules.Count
    review_findings=$review.Count
    orphan_candidates=$orphans.Count
    broad_rule_review=$broad.Count
    findings=$findings
    policy=[ordered]@{
        scanner='OBSERVE_AND_CLASSIFY'
        automatic_cleanup='DENIED'
        human_gate='REQUIRED_FOR_FUTURE_MUTATION'
        orphan_is_not_vulnerability='TRUE'
        principle='Explain evidence before proposing mutation.'
    }
}

$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $json -Encoding utf8

@"
============================================================
 VERTEX SECURITY HYGIENE REPORT
============================================================
 Firewall Rules           : $($rules.Count)
 Review Findings          : $($review.Count)
 Orphan Candidates        : $($orphans.Count)
 Broad Rule Review        : $($broad.Count)

 Automatic Cleanup        : DENIED
 Human Gate               : REQUIRED
 Mutation                 : NONE

 JSON                     : $json
 TXT                      : $txt
============================================================
"@ | Set-Content -LiteralPath $txt -Encoding utf8

Write-Host ''
Write-Host '============================================================'
Write-Host ' SECURITY HYGIENE SCAN COMPLETE'
Write-Host " JSON : $json"
Write-Host " TXT  : $txt"
Write-Host ' ZERO MUTATION / HUMAN REVIEW REQUIRED'
Write-Host '============================================================' -ForegroundColor Green
