#requires -Version 7.0
<#
VERTEX ENV-2 V2.0.1 — WINDOWS SERVICE INVENTORY REFINEMENT
READ ONLY / ZERO SERVICE MUTATION

Fix:
  Avoid substring false positives such as:
    redis -> GameInputRedistService

Strategy:
  - exact/known service names where appropriate
  - token-aware regex for display/path matching
  - separate provider classifiers
#>

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$ReportRoot='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$ServiceRoot=Join-Path $ReportRoot '_services'
$LedgerPath=Join-Path $ServiceRoot 'VERTEX_SERVICE_OWNERSHIP_LEDGER.json'
New-Item -ItemType Directory -Path $ServiceRoot -Force | Out-Null

function Match-ServiceClass {
    param($Service)

    $name=[string]$Service.Name
    $display=[string]$Service.DisplayName
    $path=[string]$Service.PathName
    $all="$name $display $path"

    $classes=[System.Collections.Generic.List[string]]::new()

    # Vertex
    if($all -match '(?i)\bvertex\b|vertexprotocol'){ $classes.Add('VERTEX') }

    # IIS
    if($name -in @('W3SVC','WAS','IISADMIN') -or
       $all -match '(?i)\biis\b|world wide web publishing|iissvcs'){
        $classes.Add('IIS')
    }

    # Docker
    if($name -eq 'com.docker.service' -or
       $all -match '(?i)\bdocker\b'){
        $classes.Add('DOCKER')
    }

    # FileMaker
    if($all -match '(?i)\bfilemaker\b|\bfmshelper\.exe\b'){
        $classes.Add('FILEMAKER')
    }

    # PostgreSQL
    if($name -match '(?i)^postgresql' -or
       $all -match '(?i)\bpostgres(?:ql)?\b|postgres\.exe'){
        $classes.Add('POSTGRESQL')
    }

    # MySQL / MariaDB
    if($name -match '(?i)^(mysql|mariadb)' -or
       $all -match '(?i)\bmysql\b|\bmariadb\b|mysqld\.exe'){
        $classes.Add('MYSQL_MARIADB')
    }

    # Redis — deliberately strict, so "Redist" will NOT match.
    if($name -match '(?i)^redis(?:[-_].*)?$' -or
       $display -match '(?i)\bredis(?:\s+server)?\b' -or
       $path -match '(?i)(^|[\\/" ])redis(?:-server)?\.exe(\s|$|")'){
        $classes.Add('REDIS')
    }

    # Ollama
    if($name -match '(?i)^ollama' -or
       $all -match '(?i)\bollama\b|ollama\.exe'){
        $classes.Add('OLLAMA')
    }

    # Nginx
    if($name -match '(?i)^nginx' -or
       $all -match '(?i)\bnginx\b|nginx\.exe'){
        $classes.Add('NGINX')
    }

    # Caddy
    if($name -match '(?i)^caddy' -or
       $all -match '(?i)\bcaddy\b|caddy\.exe'){
        $classes.Add('CADDY')
    }

    # Apache
    if($name -match '(?i)^(apache|httpd)' -or
       $all -match '(?i)\bapache\b|\bhttpd\b|httpd\.exe'){
        $classes.Add('APACHE')
    }

    # Node services, strict executable match.
    if($path -match '(?i)(^|[\\/" ])node\.exe(\s|$|")'){
        $classes.Add('NODE')
    }

    return @($classes | Sort-Object -Unique)
}

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.0.1 — SERVICE INVENTORY REFINEMENT' -ForegroundColor Magenta
Write-Host ' TOKEN-AWARE CLASSIFICATION / FALSE-POSITIVE GUARD' -ForegroundColor Magenta
Write-Host ' READ ONLY / ZERO SERVICE MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$all=@(Get-CimInstance Win32_Service | Sort-Object Name)
$inventory=@()

foreach($s in $all){
    $classes=@(Match-ServiceClass -Service $s)
    if($classes.Count -eq 0){ continue }

    $inventory += [pscustomobject][ordered]@{
        name=$s.Name
        display_name=$s.DisplayName
        state=$s.State
        start_mode=$s.StartMode
        start_name=$s.StartName
        path_name=$s.PathName
        process_id=$s.ProcessId
        classes=$classes
        ownership='PRE_EXISTING_NOT_OWNED'
        mutation_allowed=$false
        rollback_eligible=$false
    }
}

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$json=Join-Path $ReportRoot "VERTEX_SERVICE_INVENTORY_REFINED.$stamp.json"
$txt=Join-Path $ReportRoot "VERTEX_SERVICE_INVENTORY_REFINED.$stamp.txt"

$report=[ordered]@{
    schema='vertex.service.inventory-report.v1.1'
    mission='VERTEX_ENV_2_V2_0_1_SERVICE_INVENTORY_REFINEMENT'
    generated_at=(Get-Date).ToString('o')
    mode='READ_ONLY'
    total_services=$all.Count
    relevant_services=$inventory.Count
    services=$inventory
    false_positive_guards=@(
        'redis does not substring-match Redist',
        'node requires node.exe path',
        'IIS uses known names/tokens'
    )
    safety=[ordered]@{
        create='DENIED'
        modify='DENIED'
        start='DENIED'
        stop='DENIED'
        delete='DENIED'
    }
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $json -Encoding utf8

$lines=[System.Collections.Generic.List[string]]::new()
$lines.Add('============================================================')
$lines.Add(' VERTEX WINDOWS SERVICE INVENTORY — REFINED')
$lines.Add('============================================================')
$lines.Add(" Total services      : $($all.Count)")
$lines.Add(" Relevant services   : $($inventory.Count)")
$lines.Add('')

foreach($s in $inventory){
    $lines.Add("[PRE_EXISTING_PROTECTED] $($s.name)")
    $lines.Add("  Class     : $($s.classes -join ', ')")
    $lines.Add("  Display   : $($s.display_name)")
    $lines.Add("  State     : $($s.state)")
    $lines.Add("  StartMode : $($s.start_mode)")
    $lines.Add("  Account   : $($s.start_name)")
    $lines.Add("  Path      : $($s.path_name)")
}

$lines.Add('')
$lines.Add('FALSE POSITIVE GUARD')
$lines.Add('  "redis" will NOT match "Redist"')
$lines.Add('')
$lines.Add("JSON : $json")
$lines.Add("TXT  : $txt")
$lines.Add('============================================================')

$lines -join [Environment]::NewLine | Set-Content -LiteralPath $txt -Encoding utf8
Write-Host ($lines -join [Environment]::NewLine)
Write-Host ''
Write-Host 'SERVICE INVENTORY REFINEMENT : GREEN (READ-ONLY)' -ForegroundColor Green
