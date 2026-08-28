#requires -Version 7.0
<#
VERTEX ENV-2 V2.4 — FIREWALL OWNERSHIP FOUNDATION
READ ONLY / ZERO FIREWALL MUTATION

Purpose:
  Inventory relevant Windows Defender Firewall rules and establish
  the ownership boundary for future Vertex firewall deployment.

V2.4 NEVER creates, enables, disables, modifies, or deletes rules.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$ReportRoot='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$FirewallRoot=Join-Path $ReportRoot '_firewall'
$LedgerPath=Join-Path $FirewallRoot 'VERTEX_FIREWALL_OWNERSHIP_LEDGER.json'
New-Item -ItemType Directory -Path $FirewallRoot -Force | Out-Null

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.4 — FIREWALL OWNERSHIP FOUNDATION' -ForegroundColor Magenta
Write-Host ' INVENTORY -> EVIDENCE -> FUTURE RESTORE ELIGIBILITY' -ForegroundColor Magenta
Write-Host ' READ ONLY / ZERO FIREWALL MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

if(-not (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue)){
    throw 'Get-NetFirewallRule is unavailable on this host.'
}

$rules=@(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop)
$inventory=@()

foreach($rule in $rules){
    $app=$null
    $port=$null

    try { $app=$rule | Get-NetFirewallApplicationFilter -ErrorAction Stop }
    catch {}
    try { $port=$rule | Get-NetFirewallPortFilter -ErrorAction Stop }
    catch {}

    $program=if($app){[string]$app.Program}else{''}
    $localPort=if($port){[string]$port.LocalPort}else{''}
    $remotePort=if($port){[string]$port.RemotePort}else{''}
    $protocol=if($port){[string]$port.Protocol}else{''}

    $text=(
        [string]$rule.Name + ' ' +
        [string]$rule.DisplayName + ' ' +
        [string]$rule.Group + ' ' +
        $program
    )

    $classes=[System.Collections.Generic.List[string]]::new()

    if($text -match '(?i)\bvertex\b|vertexprotocol'){ $classes.Add('VERTEX') }
    if($text -match '(?i)\bfilemaker\b'){ $classes.Add('FILEMAKER') }
    if($text -match '(?i)\bdocker\b'){ $classes.Add('DOCKER') }
    if($text -match '(?i)\bcloudflared\b|\bcloudflare\b'){ $classes.Add('CLOUDFLARE') }
    if($text -match '(?i)\bnginx\b'){ $classes.Add('NGINX') }
    if($text -match '(?i)\bapache\b|\bhttpd\b'){ $classes.Add('APACHE') }
    if($text -match '(?i)\biis\b|world wide web'){ $classes.Add('IIS') }
    if($text -match '(?i)\bpostgres(?:ql)?\b'){ $classes.Add('POSTGRESQL') }
    if($text -match '(?i)\bollama\b'){ $classes.Add('OLLAMA') }

    if($classes.Count -eq 0){ continue }

    $inventory += [pscustomobject][ordered]@{
        name=[string]$rule.Name
        display_name=[string]$rule.DisplayName
        group=[string]$rule.Group
        enabled=[string]$rule.Enabled
        direction=[string]$rule.Direction
        action=[string]$rule.Action
        profile=[string]$rule.Profile
        program=$program
        protocol=$protocol
        local_port=$localPort
        remote_port=$remotePort
        classes=@($classes | Sort-Object -Unique)
        ownership='PRE_EXISTING_NOT_OWNED'
        rollback_eligible=$false
    }
}

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$json=Join-Path $ReportRoot "VERTEX_FIREWALL_INVENTORY.$stamp.json"
$txt=Join-Path $ReportRoot "VERTEX_FIREWALL_INVENTORY.$stamp.txt"

$report=[ordered]@{
    schema='vertex.firewall.inventory-report.v1'
    mission='VERTEX_ENV_2_V2_4_FIREWALL_OWNERSHIP_FOUNDATION'
    generated_at=(Get-Date).ToString('o')
    mode='READ_ONLY'
    total_rules=$rules.Count
    relevant_rules=$inventory.Count
    rules=$inventory
    ownership_policy=[ordered]@{
        pre_existing='PROTECTED'
        vertex_created='FUTURE_DELETE_ONLY_IF_LIVE_MATCHES_EVIDENCE'
        vertex_modified='FUTURE_RESTORE_ONLY_IF_LIVE_MATCHES_VERTEX_POST_STATE'
        third_party_changed='AUTO_ROLLBACK_DENIED'
    }
    safety=[ordered]@{
        create='DENIED'
        modify='DENIED'
        enable_disable='DENIED'
        delete='DENIED'
    }
}

$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $json -Encoding utf8

if(-not(Test-Path -LiteralPath $LedgerPath)){
    [ordered]@{
        schema='vertex.firewall.ownership-ledger.v1'
        updated_at=(Get-Date).ToString('o')
        records=@()
        notes=@(
            'Empty ownership ledger created in report area only.',
            'No firewall ownership is inferred from inventory.',
            'Pre-existing firewall rules are protected by default.'
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $LedgerPath -Encoding utf8
}

$lines=[System.Collections.Generic.List[string]]::new()
$lines.Add('============================================================')
$lines.Add(' VERTEX WINDOWS FIREWALL INVENTORY')
$lines.Add('============================================================')
$lines.Add(" Total rules          : $($rules.Count)")
$lines.Add(" Relevant rules       : $($inventory.Count)")
$lines.Add('')

foreach($r in $inventory){
    $lines.Add("[PRE_EXISTING_PROTECTED] $($r.display_name)")
    $lines.Add("  Class      : $($r.classes -join ', ')")
    $lines.Add("  Direction  : $($r.direction)")
    $lines.Add("  Action     : $($r.action)")
    $lines.Add("  Enabled    : $($r.enabled)")
    $lines.Add("  Program    : $($r.program)")
    $lines.Add("  Protocol   : $($r.protocol)")
    $lines.Add("  LocalPort  : $($r.local_port)")
}

$lines.Add('')
$lines.Add('SAFETY')
$lines.Add(' Create / Modify / Enable / Disable / Delete : DENIED')
$lines.Add(' Existing firewall ownership                 : NOT CLAIMED')
$lines.Add('')
$lines.Add("Ledger : $LedgerPath")
$lines.Add("JSON   : $json")
$lines.Add("TXT    : $txt")
$lines.Add('============================================================')

$lines -join [Environment]::NewLine | Set-Content -LiteralPath $txt -Encoding utf8
Write-Host ($lines -join [Environment]::NewLine)
Write-Host ''
Write-Host 'FIREWALL OWNERSHIP FOUNDATION : GREEN (READ-ONLY)' -ForegroundColor Green
