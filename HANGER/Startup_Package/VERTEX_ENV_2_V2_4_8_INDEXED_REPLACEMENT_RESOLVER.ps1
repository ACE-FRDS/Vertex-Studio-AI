#requires -Version 7.0
<#
VERTEX ENV-2 V2.4.8 — INDEXED REPLACEMENT RESOLVER
READ ONCE / INDEX FIRST / ZERO MUTATION

Consumes newest V2.4.5 remediation plan.

Design:
  1. Collect replacement evidence ONCE.
  2. Build an in-memory executable index.
  3. Resolve all candidates against that index.
  4. Never recurse entire Program Files / LOCALAPPDATA for each candidate.
  5. No firewall mutation.

This is a read-only optimization of V2.4.7.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.4.8 — INDEXED REPLACEMENT RESOLVER' -ForegroundColor Magenta
Write-Host ' READ ONCE -> BUILD INDEX -> RESOLVE IN MEMORY' -ForegroundColor Magenta
Write-Host ' READ ONLY / ZERO MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$source = Get-ChildItem -LiteralPath $ReportRoot -Filter 'VERTEX_HYGIENE_REMEDIATION_PLAN.*.json' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $source) {
    throw 'No V2.4.5 remediation plan JSON found.'
}

$data = Get-Content -LiteralPath $source.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 50
$rawCandidates = @($data.plan | Where-Object proposed_decision -eq 'LIKELY_REMOVE')

Write-Host "Source         : $($source.FullName)"
Write-Host "Raw candidates : $($rawCandidates.Count)"

function Normalize-Path {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return $Path.Trim().Trim('"').ToLowerInvariant()
}

function Get-Family {
    param([string]$DisplayName,[string]$Program)
    $s="$DisplayName $Program"
    switch -Regex ($s) {
        '(?i)filemaker'                  { return 'FILEMAKER' }
        '(?i)rustrover'                  { return 'JETBRAINS_RUSTROVER' }
        '(?i)rider'                      { return 'JETBRAINS_RIDER' }
        '(?i)pycharm'                    { return 'JETBRAINS_PYCHARM' }
        '(?i)webstorm'                   { return 'JETBRAINS_WEBSTORM' }
        '(?i)datagrip'                   { return 'JETBRAINS_DATAGRIP' }
        '(?i)intellij|idea64'            { return 'JETBRAINS_INTELLIJ' }
        '(?i)edgewebview|msedgewebview2' { return 'EDGE_WEBVIEW2' }
        '(?i)nginx'                      { return 'NGINX' }
        '(?i)premiere'                   { return 'ADOBE_PREMIERE' }
        '(?i)creative cloud'             { return 'ADOBE_CREATIVE_CLOUD' }
        '(?i)javaw|openjdk|jdk-'         { return 'JAVA_JDK' }
        '(?i)steamwebhelper|steam'       { return 'STEAM' }
        '(?i)epicwebhelper|epic games'   { return 'EPIC' }
        '(?i)streamdeck|elgato'          { return 'STREAMDECK' }
        '(?i)epson'                      { return 'EPSON' }
        '(?i)armoury|asus|acsetup'       { return 'ASUS_ARMOURY' }
        '(?i)ldplayer|ld9box'            { return 'LDPLAYER' }
        '(?i)bignox|nox'                 { return 'NOX' }
        '(?i)node\.exe|node20\.exe'      { return 'NODE_RUNTIME' }
        default                          { return 'OTHER' }
    }
}

function Add-IndexEntry {
    param(
        [hashtable]$Index,
        [string]$Path,
        [string]$Source
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }

    $clean=$Path.Trim().Trim('"')
    if (-not(Test-Path -LiteralPath $clean -PathType Leaf -ErrorAction SilentlyContinue)) { return }

    $leaf=[IO.Path]::GetFileName($clean).ToLowerInvariant()
    if (-not $Index.ContainsKey($leaf)) {
        $Index[$leaf]=[System.Collections.Generic.List[object]]::new()
    }

    $Index[$leaf].Add([pscustomobject][ordered]@{
        path=$clean
        source=$Source
    })
}

function Get-ExecutableNameForFamily {
    param([string]$Family)

    return @(
        switch ($Family) {
            'FILEMAKER'           { 'filemaker pro.exe' }
            'JETBRAINS_RUSTROVER' { 'rustrover64.exe' }
            'JETBRAINS_RIDER'     { 'rider64.exe' }
            'JETBRAINS_PYCHARM'   { 'pycharm64.exe' }
            'JETBRAINS_WEBSTORM'  { 'webstorm64.exe' }
            'JETBRAINS_DATAGRIP'  { 'datagrip64.exe' }
            'JETBRAINS_INTELLIJ'  { 'idea64.exe' }
            'EDGE_WEBVIEW2'       { 'msedgewebview2.exe' }
            'NGINX'               { 'nginx.exe' }
            'ADOBE_PREMIERE'      { 'adobe premiere pro.exe' }
            'JAVA_JDK'            { 'javaw.exe' }
            'STEAM'               { 'steamwebhelper.exe' }
            'EPIC'                { 'epicwebhelper.exe' }
            'STREAMDECK'          { 'node20.exe'; 'streamdeck.exe' }
            default               { }
        }
    )
}

function Get-TargetRoots {
    $roots=[System.Collections.Generic.List[string]]::new()

    $known=@(
        "$env:ProgramFiles\FileMaker",
        "$env:ProgramFiles\JetBrains",
        "${env:ProgramFiles(x86)}\JetBrains",
        "$env:LOCALAPPDATA\Programs\JetBrains",
        "$env:LOCALAPPDATA\JetBrains",
        "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application",
        "$env:ProgramFiles\Microsoft\EdgeWebView\Application",
        "$env:ProgramFiles\Adobe",
        "${env:ProgramFiles(x86)}\Adobe",
        "$env:ProgramFiles\Eclipse Adoptium",
        "${env:ProgramFiles(x86)}\Eclipse Adoptium",
        "${env:ProgramFiles(x86)}\Steam",
        "$env:ProgramFiles\Epic Games",
        "${env:ProgramFiles(x86)}\Epic Games",
        "$env:ProgramFiles\Elgato",
        "${env:ProgramFiles(x86)}\Elgato",
        'C:\nginx',
        'C:\nginx-1.26.3'
    )

    foreach($r in $known) {
        if ($r -and (Test-Path -LiteralPath $r -PathType Container -ErrorAction SilentlyContinue)) {
            $roots.Add($r)
        }
    }

    # Add InstallLocation roots ONCE from uninstall registry.
    $uninstallKeys=@(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach($k in $uninstallKeys) {
        try {
            foreach($app in @(Get-ItemProperty $k -ErrorAction SilentlyContinue)) {
                $loc=[string]$app.InstallLocation
                if ($loc -and (Test-Path -LiteralPath $loc -PathType Container -ErrorAction SilentlyContinue)) {
                    $roots.Add($loc)
                }
            }
        } catch {}
    }

    return @($roots | Select-Object -Unique)
}

$wantedNames=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach($c in $rawCandidates) {
    $family=Get-Family -DisplayName ([string]$c.display_name) -Program ([string]$c.program)
    foreach($name in @(Get-ExecutableNameForFamily $family)) {
        if($name){ [void]$wantedNames.Add($name) }
    }

    $oldLeaf=[IO.Path]::GetFileName(([string]$c.program).Trim().Trim('"'))
    if($oldLeaf){ [void]$wantedNames.Add($oldLeaf) }
}

Write-Host "Wanted EXE names: $($wantedNames.Count)"

$index=@{}

# 1) Existing firewall program paths — one pass
Write-Host '[1/4] INDEX FIREWALL PROGRAM PATHS'
try {
    $rules=@(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop)
    $apps=@(Get-NetFirewallApplicationFilter -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
    foreach($a in $apps) {
        $p=[string]$a.Program
        if($p -match '^[A-Za-z]:\\') {
            Add-IndexEntry -Index $index -Path $p -Source 'FIREWALL_LIVE_PATH'
        }
    }
} catch {}

# 2) Service executable paths — one pass
Write-Host '[2/4] INDEX SERVICE PATHS'
try {
    foreach($svc in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
        $raw=[string]$svc.PathName
        if([string]::IsNullOrWhiteSpace($raw)){ continue }

        $exe=$null
        if($raw -match '^\s*"([^"]+\.exe)"') {
            $exe=$Matches[1]
        }
        elseif($raw -match '^\s*([A-Za-z]:\\.*?\.exe)(?:\s|$)') {
            $exe=$Matches[1]
        }

        if($exe) {
            Add-IndexEntry -Index $index -Path $exe -Source 'WINDOWS_SERVICE'
        }
    }
} catch {}

# 3) Installed application DisplayIcon — one pass
Write-Host '[3/4] INDEX INSTALLED APP ICON/PATHS'
$uninstallKeys=@(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

foreach($k in $uninstallKeys) {
    try {
        foreach($app in @(Get-ItemProperty $k -ErrorAction SilentlyContinue)) {
            $icon=[string]$app.DisplayIcon
            if($icon) {
                $iconPath=($icon -replace ',\d+$','').Trim().Trim('"')
                if($iconPath -match '\.exe$') {
                    Add-IndexEntry -Index $index -Path $iconPath -Source 'INSTALLED_APP_DISPLAYICON'
                }
            }
        }
    } catch {}
}

# 4) Targeted roots only — each root scanned once, only wanted filenames retained
Write-Host '[4/4] INDEX TARGETED APPLICATION ROOTS'
$roots=@(Get-TargetRoots)
Write-Host "Target roots: $($roots.Count)"

$rootNo=0
foreach($root in $roots) {
    $rootNo++
    Write-Progress -Activity 'Vertex Indexed Replacement Resolver' -Status "$rootNo / $($roots.Count) : $root" -PercentComplete (($rootNo/$roots.Count)*100)

    try {
        foreach($file in @(Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue)) {
            if($wantedNames.Contains($file.Name)) {
                Add-IndexEntry -Index $index -Path $file.FullName -Source "TARGET_ROOT:$root"
            }
        }
    } catch {}
}
Write-Progress -Activity 'Vertex Indexed Replacement Resolver' -Completed

Write-Host "Indexed EXE names : $($index.Keys.Count)"

# Deduplicate candidates by display + old program
$groups=$rawCandidates | Group-Object {
    $d=([string]$_.display_name).ToLowerInvariant()
    $p=Normalize-Path ([string]$_.program)
    "$d|$p"
}

$resolved=@()
$n=0

foreach($g in $groups) {
    $n++
    $items=@($g.Group)
    $first=$items[0]

    $display=[string]$first.display_name
    $oldProgram=[string]$first.program
    $oldNorm=Normalize-Path $oldProgram
    $family=Get-Family -DisplayName $display -Program $oldProgram

    $searchNames=@(Get-ExecutableNameForFamily $family)
    if($searchNames.Count -eq 0) {
        $leaf=[IO.Path]::GetFileName($oldProgram.Trim().Trim('"'))
        if($leaf){$searchNames=@($leaf)}
    }

    $replacementHits=[System.Collections.Generic.List[object]]::new()

    foreach($name in $searchNames) {
        $key=$name.ToLowerInvariant()
        if($index.ContainsKey($key)) {
            foreach($hit in @($index[$key])) {
                if((Normalize-Path ([string]$hit.path) -ne $oldNorm)) {
                    $replacementHits.Add($hit)
                }
            }
        }
    }

    $uniqueHits=@($replacementHits | Sort-Object path -Unique)
    $liveOld=$false
    if($oldProgram -and $oldProgram -notin @('Any','System')) {
        $liveOld=Test-Path -LiteralPath $oldProgram.Trim().Trim('"') -PathType Leaf -ErrorAction SilentlyContinue
    }

    $decision='HOLD_FOR_HUMAN'
    $confidence=0.80
    $reasons=[System.Collections.Generic.List[string]]::new()

    if($liveOld) {
        $decision='PROTECT_LIVE_RETURNED'
        $confidence=0.99
        $reasons.Add('Original executable exists again.')
    }
    elseif($uniqueHits.Count -gt 0) {
        $decision='REPLACEMENT_DETECTED'
        $confidence=0.95
        $reasons.Add('Replacement/current executable found in prebuilt index.')
    }
    elseif($family -eq 'OTHER') {
        $decision='READY_FOR_HUMAN_APPROVAL'
        $confidence=0.92
        $reasons.Add('Old executable remains absent.')
        $reasons.Add('No indexed replacement evidence found.')
        $reasons.Add('V2.4.5 found no service/app/listener evidence.')
    }
    else {
        $decision='HOLD_FOR_HUMAN'
        $confidence=0.90
        $reasons.Add('Known application family but no indexed replacement detected.')
        $reasons.Add('Manual confirmation required before future mutation.')
    }

    $resolved += [pscustomobject][ordered]@{
        candidate_id=('IDX-{0:D4}' -f $n)
        display_name=$display
        family=$family
        old_program=$oldProgram
        firewall_rule_names=@($items | ForEach-Object firewall_rule_name | Select-Object -Unique)
        duplicate_rule_count=@($items | ForEach-Object firewall_rule_name | Select-Object -Unique).Count
        original_exists_now=$liveOld
        replacement_evidence=$uniqueHits
        gate_decision=$decision
        confidence=$confidence
        reasons=@($reasons)
        mutation='NONE'
    }
}

$counts=[ordered]@{
    RAW_LIKELY_REMOVE=$rawCandidates.Count
    UNIQUE_CANDIDATES=$resolved.Count
    READY_FOR_HUMAN_APPROVAL=@($resolved | Where-Object gate_decision -eq 'READY_FOR_HUMAN_APPROVAL').Count
    REPLACEMENT_DETECTED=@($resolved | Where-Object gate_decision -eq 'REPLACEMENT_DETECTED').Count
    PROTECT_LIVE_RETURNED=@($resolved | Where-Object gate_decision -eq 'PROTECT_LIVE_RETURNED').Count
    HOLD_FOR_HUMAN=@($resolved | Where-Object gate_decision -eq 'HOLD_FOR_HUMAN').Count
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' INDEXED REPLACEMENT RESOLUTION SUMMARY'
Write-Host '============================================================'
Write-Host " Raw candidates            : $($counts.RAW_LIKELY_REMOVE)"
Write-Host " Unique candidates         : $($counts.UNIQUE_CANDIDATES)"
Write-Host " Ready for human approval  : $($counts.READY_FOR_HUMAN_APPROVAL)" -ForegroundColor Yellow
Write-Host " Replacement detected      : $($counts.REPLACEMENT_DETECTED)" -ForegroundColor Cyan
Write-Host " Live returned / protect   : $($counts.PROTECT_LIVE_RETURNED)" -ForegroundColor Green
Write-Host " Hold for human            : $($counts.HOLD_FOR_HUMAN)"

foreach($x in $resolved) {
    if($x.gate_decision -eq 'PROTECT_LIVE_RETURNED'){continue}
    $color = switch($x.gate_decision) {
        'READY_FOR_HUMAN_APPROVAL' {'Yellow'}
        'REPLACEMENT_DETECTED' {'Cyan'}
        default {'Gray'}
    }

    Write-Host ''
    Write-Host "[$($x.gate_decision)] $($x.candidate_id) $($x.display_name)" -ForegroundColor $color
    Write-Host "  Family      : $($x.family)"
    Write-Host "  Old Program : $($x.old_program)"
    Write-Host "  Rule Count  : $($x.duplicate_rule_count)"
    if(@($x.replacement_evidence).Count -gt 0) {
        Write-Host "  Replacement : $((@($x.replacement_evidence) | ForEach-Object path) -join ' | ')"
    }
    Write-Host "  Reason      : $($x.reasons -join ' | ')"
}

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$json=Join-Path $ReportRoot "VERTEX_INDEXED_REPLACEMENT_RESOLUTION.$stamp.json"
$txt=Join-Path $ReportRoot "VERTEX_INDEXED_REPLACEMENT_RESOLUTION.$stamp.txt"

$report=[ordered]@{
    schema='vertex.environment.indexed-replacement-resolution.v1'
    mission='VERTEX_ENV_2_V2_4_8_INDEXED_REPLACEMENT_RESOLVER'
    generated_at=(Get-Date).ToString('o')
    source_report=$source.FullName
    mode='READ_ONLY'
    index_stats=[ordered]@{
        wanted_executable_names=$wantedNames.Count
        indexed_executable_names=$index.Keys.Count
        targeted_roots=$roots.Count
    }
    counts=$counts
    candidates=$resolved
    policy=[ordered]@{
        repeated_full_disk_scan='DENIED'
        automatic_delete='DENIED'
        mutation='NONE'
        human_gate='REQUIRED'
        principle='Read once, index once, resolve in memory.'
    }
}

$report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX ENV-2 V2.4.8 — INDEXED REPLACEMENT RESOLVER',
    '============================================================',
    " Source                    : $($source.FullName)",
    " Raw candidates            : $($counts.RAW_LIKELY_REMOVE)",
    " Unique candidates         : $($counts.UNIQUE_CANDIDATES)",
    " Ready for human approval  : $($counts.READY_FOR_HUMAN_APPROVAL)",
    " Replacement detected      : $($counts.REPLACEMENT_DETECTED)",
    " Live returned / protect   : $($counts.PROTECT_LIVE_RETURNED)",
    " Hold for human            : $($counts.HOLD_FOR_HUMAN)",
    " Indexed EXE names         : $($index.Keys.Count)",
    " Target roots              : $($roots.Count)",
    '',
    ' Mutation                  : NONE',
    ' Automatic delete          : DENIED',
    ' Human gate                : REQUIRED',
    '',
    " JSON                      : $json",
    " TXT                       : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' V2.4.8 INDEXED RESOLVER : GREEN' -ForegroundColor Green
Write-Host " JSON : $json"
Write-Host " TXT  : $txt"
Write-Host ' READ ONCE / ZERO MUTATION' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
