#requires -Version 7.0
<#
VERTEX ENV-2 V2.4.9 — REPLACEMENT IDENTITY RESOLVER
V2.4.8 INDEX -> VENDOR -> PRODUCT -> FAMILY -> VERSION/PATH LINEAGE -> HUMAN GATE

PURPOSE
  Refine V2.4.8 replacement candidates without changing Windows state.
  "Same EXE name" is evidence, not proof of replacement identity.

SAFETY
  READ ONLY / ZERO MUTATION
  NO firewall/service/registry/file deletion or modification.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.4.9 — REPLACEMENT IDENTITY RESOLVER' -ForegroundColor Magenta
Write-Host ' VENDOR -> PRODUCT -> FAMILY -> LINEAGE -> HUMAN GATE' -ForegroundColor Magenta
Write-Host ' READ ONLY / ZERO MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$source = Get-ChildItem -LiteralPath $ReportRoot -Filter 'VERTEX_INDEXED_REPLACEMENT_RESOLUTION.*.json' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $source) { throw 'No V2.4.8 indexed replacement report JSON found.' }

$data = Get-Content -LiteralPath $source.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 50
$candidates = @($data.candidates)

Write-Host "Source      : $($source.FullName)"
Write-Host "Candidates  : $($candidates.Count)"

function Normalize-Path {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return $Path.Trim().Trim('"').Replace('/','\').ToLowerInvariant()
}

function Get-PathTokens {
    param([AllowNull()][string]$Path)
    $p = Normalize-Path $Path
    if (-not $p) { return @() }
    return @($p -split '[\\\s._()\-]+' | Where-Object { $_ -and $_.Length -ge 3 })
}

function Get-FileIdentity {
    param([AllowNull()][string]$Path)

    $result = [ordered]@{
        path              = $Path
        exists            = $false
        company           = ''
        product           = ''
        description       = ''
        file_version      = ''
        product_version   = ''
        original_filename = ''
        leaf              = ''
    }

    if ([string]::IsNullOrWhiteSpace($Path)) { return [pscustomobject]$result }

    $clean = $Path.Trim().Trim('"')
    $result.leaf = [IO.Path]::GetFileName($clean)

    if (-not (Test-Path -LiteralPath $clean -PathType Leaf -ErrorAction SilentlyContinue)) {
        return [pscustomobject]$result
    }

    $result.exists = $true
    try {
        $v = (Get-Item -LiteralPath $clean -ErrorAction Stop).VersionInfo
        $result.company           = [string]$v.CompanyName
        $result.product           = [string]$v.ProductName
        $result.description       = [string]$v.FileDescription
        $result.file_version      = [string]$v.FileVersion
        $result.product_version   = [string]$v.ProductVersion
        $result.original_filename = [string]$v.OriginalFilename
    } catch {}

    return [pscustomobject]$result
}

function Get-AppIdentityCatalog {
    $catalog = [System.Collections.Generic.List[object]]::new()
    $keys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($key in $keys) {
        try {
            foreach ($app in @(Get-ItemProperty $key -ErrorAction SilentlyContinue)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$app.DisplayName)) {
                    $catalog.Add([pscustomobject][ordered]@{
                        display_name     = [string]$app.DisplayName
                        publisher        = [string]$app.Publisher
                        display_version  = [string]$app.DisplayVersion
                        install_location = [string]$app.InstallLocation
                        display_icon     = [string]$app.DisplayIcon
                    })
                }
            }
        } catch {}
    }
    return @($catalog)
}

function Find-AppContext {
    param(
        [object[]]$Catalog,
        [AllowNull()][string]$Path,
        [AllowNull()][string]$DisplayName
    )

    $p = Normalize-Path $Path
    $best = $null
    $bestScore = -1

    foreach ($app in @($Catalog)) {
        $score = 0
        $loc = Normalize-Path ([string]$app.install_location)
        if ($p -and $loc -and $p.StartsWith($loc)) { $score += 8 }

        $dn = ([string]$app.display_name).ToLowerInvariant()
        $wanted = ([string]$DisplayName).ToLowerInvariant()
        if ($dn -and $wanted) {
            if ($dn -eq $wanted) { $score += 5 }
            elseif ($wanted.Contains($dn) -or $dn.Contains($wanted)) { $score += 3 }
        }

        if ($score -gt $bestScore) {
            $best = $app
            $bestScore = $score
        }
    }

    if ($bestScore -le 0) { return $null }
    return $best
}

function Get-CanonicalVendor {
    param([string]$Text)
    $s = $Text.ToLowerInvariant()
    switch -Regex ($s) {
        'filemaker|claris'              { return 'CLARIS_FILEMAKER' }
        'jetbrains'                     { return 'JETBRAINS' }
        'microsoft'                     { return 'MICROSOFT' }
        'adobe'                         { return 'ADOBE' }
        'epic games|epicgames|unreal'   { return 'EPIC_GAMES' }
        'valve|steam'                   { return 'VALVE_STEAM' }
        'elgato|corsair'                { return 'ELGATO_CORSAIR' }
        'oracle|adoptium|openjdk|java'  { return 'JAVA_RUNTIME' }
        'nginx'                         { return 'NGINX' }
        'asus'                          { return 'ASUS' }
        'epson'                         { return 'EPSON' }
        'ldplayer|xuanzhi'              { return 'LDPLAYER' }
        'nox|bignox'                    { return 'NOX' }
        default                         { return 'UNKNOWN' }
    }
}

function Get-CanonicalProduct {
    param([string]$Text)
    $s = $Text.ToLowerInvariant()
    switch -Regex ($s) {
        'filemaker pro'                 { return 'FILEMAKER_PRO' }
        'rustrover'                     { return 'RUSTROVER' }
        'rider'                         { return 'RIDER' }
        'pycharm'                       { return 'PYCHARM' }
        'webstorm'                      { return 'WEBSTORM' }
        'datagrip'                      { return 'DATAGRIP' }
        'intellij|idea64'               { return 'INTELLIJ_IDEA' }
        'edge webview|webview2|msedgewebview2' { return 'EDGE_WEBVIEW2' }
        'premiere'                      { return 'PREMIERE_PRO' }
        'creative cloud'                { return 'CREATIVE_CLOUD' }
        'epic games launcher'           { return 'EPIC_GAMES_LAUNCHER' }
        'unreal editor|ue4editor|ue5editor' { return 'UNREAL_EDITOR' }
        'steam'                         { return 'STEAM' }
        'stream deck|streamdeck'        { return 'STREAM_DECK' }
        'nginx'                         { return 'NGINX' }
        default                         { return 'UNKNOWN' }
    }
}

function Get-MajorVersion {
    param([AllowNull()][string]$Version,[AllowNull()][string]$Path)
    foreach ($s in @($Version,$Path)) {
        if ($s -match '(?<!\d)(20\d{2})(?!\d)') { return [int]$Matches[1] }
        if ($s -match '(?<!\d)(\d{1,3})(?:\.\d+){1,3}') { return [int]$Matches[1] }
    }
    return $null
}

function Get-IdentityEvidence {
    param(
        [object]$Candidate,
        [object]$Hit,
        [object[]]$Catalog
    )

    $oldPath = [string]$Candidate.old_program
    $newPath = [string]$Hit.path
    $display = [string]$Candidate.display_name
    $family  = [string]$Candidate.family

    $newFile = Get-FileIdentity $newPath
    $newApp  = Find-AppContext -Catalog $Catalog -Path $newPath -DisplayName $display

    # Old executable may be absent. Infer old identity from rule display/family/path.
    $oldText = "$display $family $oldPath"
    $newText = "$($newFile.company) $($newFile.product) $($newFile.description) $($newFile.original_filename) $newPath"
    if ($newApp) { $newText += " $($newApp.display_name) $($newApp.publisher)" }

    $oldVendor  = Get-CanonicalVendor $oldText
    $newVendor  = Get-CanonicalVendor $newText
    $oldProduct = Get-CanonicalProduct $oldText
    $newProduct = Get-CanonicalProduct $newText

    $score = 0
    $reasons = [System.Collections.Generic.List[string]]::new()
    $rejects = [System.Collections.Generic.List[string]]::new()

    # Vendor identity
    if ($oldVendor -ne 'UNKNOWN' -and $newVendor -eq $oldVendor) {
        $score += 30
        $reasons.Add("Vendor match: $oldVendor")
    } elseif ($oldVendor -ne 'UNKNOWN' -and $newVendor -ne 'UNKNOWN' -and $newVendor -ne $oldVendor) {
        $score -= 60
        $rejects.Add("Vendor mismatch: $oldVendor -> $newVendor")
    }

    # Product identity is deliberately strict.
    if ($oldProduct -ne 'UNKNOWN' -and $newProduct -eq $oldProduct) {
        $score += 35
        $reasons.Add("Product match: $oldProduct")
    } elseif ($oldProduct -ne 'UNKNOWN' -and $newProduct -ne 'UNKNOWN' -and $newProduct -ne $oldProduct) {
        $score -= 70
        $rejects.Add("Product mismatch: $oldProduct -> $newProduct")
    }

    # Executable leaf continuity
    $oldLeaf = [IO.Path]::GetFileName($oldPath.Trim().Trim('"')).ToLowerInvariant()
    $newLeaf = [IO.Path]::GetFileName($newPath).ToLowerInvariant()
    if ($oldLeaf -and $oldLeaf -eq $newLeaf) {
        $score += 15
        $reasons.Add("Executable leaf match: $newLeaf")
    }

    # Path lineage: shared meaningful tokens, but never enough alone to confirm.
    $oldTokens = @(Get-PathTokens $oldPath)
    $newTokens = @(Get-PathTokens $newPath)
    $shared = @($oldTokens | Where-Object { $newTokens -contains $_ } | Select-Object -Unique)
    if ($shared.Count -ge 2) {
        $score += 10
        $reasons.Add("Path lineage tokens: $($shared -join ', ')")
    }

    # Version lineage: a newer/equal recognizable version is positive evidence.
    $oldMajor = Get-MajorVersion -Version '' -Path $oldPath
    $newVersion = if ($newApp -and $newApp.display_version) { [string]$newApp.display_version } else { [string]$newFile.product_version }
    $newMajor = Get-MajorVersion -Version $newVersion -Path $newPath
    if ($null -ne $oldMajor -and $null -ne $newMajor) {
        if ($newMajor -ge $oldMajor) {
            $score += 10
            $reasons.Add("Version lineage: $oldMajor -> $newMajor")
        } else {
            $score -= 10
            $rejects.Add("Version appears older: $oldMajor -> $newMajor")
        }
    }

    # Known generic/helper executables must not establish product succession by filename alone.
    if ($newLeaf -in @('node.exe','node20.exe','java.exe','javaw.exe','epicwebhelper.exe','steamwebhelper.exe')) {
        if ($oldProduct -eq 'UNKNOWN' -or $newProduct -eq 'UNKNOWN') {
            $score = [Math]::Min($score, 49)
            $rejects.Add('Generic/helper executable: product identity required.')
        }
    }

    $decision = 'HUMAN_REVIEW'
    if ($rejects.Count -gt 0 -and $score -lt 50) {
        $decision = 'REPLACEMENT_REJECTED'
    }
    elseif ($score -ge 75 -and
            ($oldProduct -eq 'UNKNOWN' -or $newProduct -eq $oldProduct) -and
            ($oldVendor -eq 'UNKNOWN' -or $newVendor -eq $oldVendor)) {
        $decision = 'REPLACEMENT_CONFIRMED'
    }
    elseif ($score -ge 50) {
        $decision = 'REPLACEMENT_PROBABLE'
    }

    return [pscustomobject][ordered]@{
        path            = $newPath
        evidence_source = [string]$Hit.source
        file_identity   = $newFile
        app_identity    = $newApp
        old_vendor      = $oldVendor
        new_vendor      = $newVendor
        old_product     = $oldProduct
        new_product     = $newProduct
        score           = $score
        decision        = $decision
        reasons         = @($reasons)
        rejects         = @($rejects)
    }
}

$catalog = @(Get-AppIdentityCatalog)
Write-Host "Installed app identities : $($catalog.Count)"

$results = [System.Collections.Generic.List[object]]::new()
$i = 0

foreach ($c in $candidates) {
    $i++
    $hits = @($c.replacement_evidence)
    $evaluated = [System.Collections.Generic.List[object]]::new()

    foreach ($hit in $hits) {
        $evaluated.Add((Get-IdentityEvidence -Candidate $c -Hit $hit -Catalog $catalog))
    }

    $ranked = @($evaluated | Sort-Object @{Expression='score';Descending=$true}, path)
    $best = if ($ranked.Count -gt 0) { $ranked[0] } else { $null }

    $final = 'NO_REPLACEMENT_EVIDENCE'
    if ($best) { $final = [string]$best.decision }

    # Preserve V2.4.8 safety states.
    if ([string]$c.gate_decision -eq 'PROTECT_LIVE_RETURNED') {
        $final = 'PROTECT_LIVE_RETURNED'
    }
    elseif ([string]$c.gate_decision -eq 'READY_FOR_HUMAN_APPROVAL' -and -not $best) {
        $final = 'READY_FOR_HUMAN_APPROVAL'
    }
    elseif ([string]$c.gate_decision -eq 'HOLD_FOR_HUMAN' -and -not $best) {
        $final = 'HOLD_FOR_HUMAN'
    }

    $results.Add([pscustomobject][ordered]@{
        candidate_id        = [string]$c.candidate_id
        display_name        = [string]$c.display_name
        family              = [string]$c.family
        old_program         = [string]$c.old_program
        firewall_rule_names = @($c.firewall_rule_names)
        v248_gate_decision  = [string]$c.gate_decision
        identity_decision   = $final
        best_replacement    = $best
        all_replacements    = $ranked
        mutation            = 'NONE'
    })

    Write-Progress -Activity 'Vertex Replacement Identity Resolver' `
        -Status "$i / $($candidates.Count) : $($c.display_name)" `
        -PercentComplete (($i / [Math]::Max(1,$candidates.Count)) * 100)
}

Write-Progress -Activity 'Vertex Replacement Identity Resolver' -Completed

$counts = [ordered]@{
    TOTAL                    = $results.Count
    REPLACEMENT_CONFIRMED    = @($results | Where-Object identity_decision -eq 'REPLACEMENT_CONFIRMED').Count
    REPLACEMENT_PROBABLE     = @($results | Where-Object identity_decision -eq 'REPLACEMENT_PROBABLE').Count
    REPLACEMENT_REJECTED     = @($results | Where-Object identity_decision -eq 'REPLACEMENT_REJECTED').Count
    HUMAN_REVIEW             = @($results | Where-Object identity_decision -eq 'HUMAN_REVIEW').Count
    READY_FOR_HUMAN_APPROVAL = @($results | Where-Object identity_decision -eq 'READY_FOR_HUMAN_APPROVAL').Count
    HOLD_FOR_HUMAN           = @($results | Where-Object identity_decision -eq 'HOLD_FOR_HUMAN').Count
    PROTECT_LIVE_RETURNED    = @($results | Where-Object identity_decision -eq 'PROTECT_LIVE_RETURNED').Count
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' REPLACEMENT IDENTITY SUMMARY'
Write-Host '============================================================'
Write-Host " Total                    : $($counts.TOTAL)"
Write-Host " Replacement confirmed    : $($counts.REPLACEMENT_CONFIRMED)" -ForegroundColor Green
Write-Host " Replacement probable     : $($counts.REPLACEMENT_PROBABLE)" -ForegroundColor Cyan
Write-Host " Replacement rejected     : $($counts.REPLACEMENT_REJECTED)" -ForegroundColor Yellow
Write-Host " Human review             : $($counts.HUMAN_REVIEW)"
Write-Host " Ready for approval       : $($counts.READY_FOR_HUMAN_APPROVAL)"
Write-Host " Hold for human           : $($counts.HOLD_FOR_HUMAN)"
Write-Host " Protect live returned    : $($counts.PROTECT_LIVE_RETURNED)"

foreach ($r in $results) {
    if ($r.identity_decision -notin @('REPLACEMENT_CONFIRMED','REPLACEMENT_PROBABLE','REPLACEMENT_REJECTED','HUMAN_REVIEW')) { continue }

    $color = switch ($r.identity_decision) {
        'REPLACEMENT_CONFIRMED' { 'Green' }
        'REPLACEMENT_PROBABLE'  { 'Cyan' }
        'REPLACEMENT_REJECTED'  { 'Yellow' }
        default                 { 'Gray' }
    }

    Write-Host ''
    Write-Host "[$($r.identity_decision)] $($r.candidate_id) $($r.display_name)" -ForegroundColor $color
    Write-Host "  Old : $($r.old_program)"
    if ($r.best_replacement) {
        Write-Host "  New : $($r.best_replacement.path)"
        Write-Host "  Score: $($r.best_replacement.score)"
        Write-Host "  Identity: $($r.best_replacement.old_vendor)/$($r.best_replacement.old_product) -> $($r.best_replacement.new_vendor)/$($r.best_replacement.new_product)"
        if (@($r.best_replacement.reasons).Count -gt 0) {
            Write-Host "  Why : $($r.best_replacement.reasons -join ' | ')"
        }
        if (@($r.best_replacement.rejects).Count -gt 0) {
            Write-Host "  Guard: $($r.best_replacement.rejects -join ' | ')"
        }
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $ReportRoot "VERTEX_REPLACEMENT_IDENTITY_RESOLUTION.$stamp.json"
$txt  = Join-Path $ReportRoot "VERTEX_REPLACEMENT_IDENTITY_RESOLUTION.$stamp.txt"

$report = [ordered]@{
    schema         = 'vertex.environment.replacement-identity-resolution.v1'
    mission        = 'VERTEX_ENV_2_V2_4_9_REPLACEMENT_IDENTITY_RESOLVER'
    generated_at   = (Get-Date).ToString('o')
    source_report  = $source.FullName
    mode           = 'READ_ONLY'
    counts         = $counts
    candidates     = @($results)
    policy         = [ordered]@{
        same_exe_name_is_proof = $false
        vendor_identity        = 'REQUIRED_WHEN_KNOWN'
        product_identity       = 'REQUIRED_WHEN_KNOWN'
        path_lineage           = 'SUPPORTING_EVIDENCE_ONLY'
        version_lineage        = 'SUPPORTING_EVIDENCE_ONLY'
        generic_helper_guard   = 'ENABLED'
        automatic_mutation     = 'DENIED'
        human_gate             = 'REQUIRED'
        mutation               = 'NONE'
    }
}

$report | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX ENV-2 V2.4.9 — REPLACEMENT IDENTITY RESOLVER',
    '============================================================',
    " Source                    : $($source.FullName)",
    " Total                     : $($counts.TOTAL)",
    " Replacement confirmed     : $($counts.REPLACEMENT_CONFIRMED)",
    " Replacement probable      : $($counts.REPLACEMENT_PROBABLE)",
    " Replacement rejected      : $($counts.REPLACEMENT_REJECTED)",
    " Human review              : $($counts.HUMAN_REVIEW)",
    " Ready for approval        : $($counts.READY_FOR_HUMAN_APPROVAL)",
    " Hold for human            : $($counts.HOLD_FOR_HUMAN)",
    " Protect live returned     : $($counts.PROTECT_LIVE_RETURNED)",
    '',
    ' Same EXE name = proof     : FALSE',
    ' Automatic mutation        : DENIED',
    ' Human gate                : REQUIRED',
    ' Mutation                  : NONE',
    '',
    " JSON                      : $json",
    " TXT                       : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' V2.4.9 IDENTITY RESOLVER : GREEN' -ForegroundColor Green
Write-Host " JSON : $json"
Write-Host " TXT  : $txt"
Write-Host ' READ ONLY / ZERO MUTATION' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
