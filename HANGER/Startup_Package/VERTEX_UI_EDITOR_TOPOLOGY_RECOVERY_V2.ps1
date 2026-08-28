& {
    $ErrorActionPreference = 'Stop'

    # ============================================================
    # VERTEX CIC — UI / EDITOR TOPOLOGY RECOVERY V2
    # Windows PowerShell 5.1 compatible
    # READ-ONLY / NO PRODUCTION MODIFICATION
    # ============================================================

    $root = 'G:\Vertex_Project\Vertex_Studio_AI'
    $authoritative =
        'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource'

    if (-not (Test-Path -LiteralPath $root)) {
        throw "Vertex root missing: $root"
    }

    if (-not (Test-Path -LiteralPath $authoritative)) {
        throw "Authoritative ProgramSource missing: $authoritative"
    }

    $reportDir = Join-Path $authoritative '_vertex_reports'
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $jsonPath = Join-Path $reportDir "UI_EDITOR_TOPOLOGY_RECOVERY.$stamp.json"
    $txtPath  = Join-Path $reportDir "UI_EDITOR_TOPOLOGY_RECOVERY.$stamp.txt"

    function Is-IgnoredPath {
        param([string]$Path)

        return (
            $Path -match '(^|\\)(node_modules|target|\.git|dist|build|coverage|\.idea|\.vscode|cache|caches)(\\|$)'
        )
    }

    function Normalize-Path {
        param([string]$Path)

        try {
            return [IO.Path]::GetFullPath($Path).TrimEnd('\')
        }
        catch {
            return $Path
        }
    }

    function Is-Under {
        param(
            [string]$Child,
            [string]$Parent
        )

        $childFull  = Normalize-Path $Child
        $parentFull = Normalize-Path $Parent

        if ($childFull.Equals(
            $parentFull,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            return $true
        }

        $prefix = $parentFull + '\'

        return $childFull.StartsWith(
            $prefix,
            [StringComparison]::OrdinalIgnoreCase
        )
    }

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' VERTEX — UI / EDITOR TOPOLOGY RECOVERY V2' -ForegroundColor Cyan
    Write-Host ' READ-ONLY / WHOLE VERTEX STUDIO AI SEARCH' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan

    # ------------------------------------------------------------
    # 1. PACKAGE / UI CANDIDATES
    # ------------------------------------------------------------

    Write-Host ''
    Write-Host '[1/6] PACKAGE / UI CANDIDATES' -ForegroundColor Yellow

    $packageFiles =
        @(
            Get-ChildItem `
                -LiteralPath $root `
                -Filter 'package.json' `
                -File `
                -Recurse `
                -ErrorAction SilentlyContinue |
            Where-Object {
                -not (Is-IgnoredPath $_.FullName)
            }
        )

    $uiCandidates =
        New-Object System.Collections.Generic.List[object]

    foreach ($packageFile in $packageFiles) {

        try {
            $package =
                Get-Content `
                    -LiteralPath $packageFile.FullName `
                    -Raw `
                    -ErrorAction Stop |
                ConvertFrom-Json
        }
        catch {
            continue
        }

        $dir =
            Split-Path -Parent $packageFile.FullName

        $depNames =
            New-Object System.Collections.Generic.HashSet[string] `
                ([StringComparer]::OrdinalIgnoreCase)

        foreach ($section in @('dependencies', 'devDependencies')) {
            if ($package.$section) {
                foreach ($property in $package.$section.PSObject.Properties) {
                    [void]$depNames.Add([string]$property.Name)
                }
            }
        }

        $score = 0
        $signals = New-Object System.Collections.Generic.List[string]

        if ($depNames.Contains('vue')) {
            $score += 25
            $signals.Add('vue')
        }

        if ($depNames.Contains('@vitejs/plugin-vue')) {
            $score += 10
            $signals.Add('vite-vue')
        }

        if ($depNames.Contains('@tauri-apps/api')) {
            $score += 25
            $signals.Add('tauri-api')
        }

        if ($depNames.Contains('@tauri-apps/cli')) {
            $score += 10
            $signals.Add('tauri-cli')
        }

        if ($depNames.Contains('quasar')) {
            $score += 12
            $signals.Add('quasar')
        }

        if ($depNames.Contains('monaco-editor')) {
            $score += 20
            $signals.Add('monaco')
        }

        if (Test-Path -LiteralPath (Join-Path $dir 'src\App.vue')) {
            $score += 20
            $signals.Add('App.vue')
        }

        if (Test-Path -LiteralPath (Join-Path $dir 'src-tauri\Cargo.toml')) {
            $score += 25
            $signals.Add('src-tauri')
        }

        $vueCount =
            @(
                Get-ChildItem `
                    -LiteralPath $dir `
                    -Filter '*.vue' `
                    -File `
                    -Recurse `
                    -ErrorAction SilentlyContinue |
                Where-Object {
                    -not (Is-IgnoredPath $_.FullName)
                }
            ).Count

        if ($vueCount -gt 0) {
            $score += [Math]::Min(15, $vueCount)
            $signals.Add("vue-files:$vueCount")
        }

        $insideAuthoritative =
            Is-Under $dir $authoritative

        if ($insideAuthoritative) {
            $score += 15
            $signals.Add('inside-authoritative')
        }

        $uiCandidates.Add(
            [pscustomobject]@{
                score = $score
                root = $dir
                package_name = [string]$package.name
                vue_files = $vueCount
                inside_authoritative = $insideAuthoritative
                signals = @($signals)
            }
        )
    }

    $uiCandidates =
        @(
            $uiCandidates |
            Sort-Object `
                @{Expression='score';Descending=$true},
                @{Expression='root';Descending=$false}
        )

    if ($uiCandidates.Count -eq 0) {
        Write-Host 'No package.json based UI candidate found.' -ForegroundColor DarkYellow
    }
    else {
        $uiCandidates |
            Select-Object -First 15 |
            Format-Table `
                score,
                package_name,
                vue_files,
                inside_authoritative,
                root `
                -AutoSize
    }

    # ------------------------------------------------------------
    # 2. RAW VUE / TAURI ROOTS WITHOUT PACKAGE MATCH
    # ------------------------------------------------------------

    Write-Host ''
    Write-Host '[2/6] RAW VUE / TAURI ROOTS' -ForegroundColor Yellow

    $appVueFiles =
        @(
            Get-ChildItem `
                -LiteralPath $root `
                -Filter 'App.vue' `
                -File `
                -Recurse `
                -ErrorAction SilentlyContinue |
            Where-Object {
                -not (Is-IgnoredPath $_.FullName)
            }
        )

    $tauriManifests =
        @(
            Get-ChildItem `
                -LiteralPath $root `
                -Filter 'Cargo.toml' `
                -File `
                -Recurse `
                -ErrorAction SilentlyContinue |
            Where-Object {
                -not (Is-IgnoredPath $_.FullName) -and
                $_.Directory.Name -eq 'src-tauri'
            }
        )

    Write-Host "App.vue files       : $($appVueFiles.Count)" -ForegroundColor Green
    Write-Host "src-tauri manifests : $($tauriManifests.Count)" -ForegroundColor Green

    foreach ($file in ($appVueFiles | Select-Object -First 20)) {
        Write-Host "  APP.VUE : $($file.FullName)"
    }

    foreach ($file in ($tauriManifests | Select-Object -First 20)) {
        Write-Host "  TAURI   : $($file.FullName)"
    }

    # ------------------------------------------------------------
    # 3. EDITOR / CONSOLE SYMBOL SEARCH
    # ------------------------------------------------------------

    Write-Host ''
    Write-Host '[3/6] EDITOR / CONSOLE SYMBOL SEARCH' -ForegroundColor Yellow

    $sourceFiles =
        @(
            Get-ChildItem `
                -LiteralPath $root `
                -Include '*.rs','*.ts','*.tsx','*.vue','*.js','*.mjs','*.json' `
                -File `
                -Recurse `
                -ErrorAction SilentlyContinue |
            Where-Object {
                -not (Is-IgnoredPath $_.FullName)
            }
        )

    $patterns = @(
        'Monaco',
        'monaco-editor',
        'EditorPort',
        'ConsoleInspector',
        'Console Inspector',
        'ObjectConsole',
        'Source Explorer',
        'Developer Agent',
        'Hyper Agent',
        'Mothership',
        'VVE'
    )

    $symbolHits =
        New-Object System.Collections.Generic.List[object]

    foreach ($pattern in $patterns) {

        $matches =
            @(
                $sourceFiles |
                Select-String `
                    -Pattern $pattern `
                    -SimpleMatch `
                    -List `
                    -ErrorAction SilentlyContinue
            )

        foreach ($match in $matches) {
            $symbolHits.Add(
                [pscustomobject]@{
                    pattern = $pattern
                    path = $match.Path
                    line = $match.LineNumber
                }
            )
        }
    }

    Write-Host "Editor/control symbol hits: $($symbolHits.Count)" -ForegroundColor Green

    $symbolHits |
        Select-Object -First 80 |
        Format-Table pattern,line,path -AutoSize

    # ------------------------------------------------------------
    # 4. AUTHORITATIVE MOTHERSHIP ANCHORS
    # ------------------------------------------------------------

    Write-Host ''
    Write-Host '[4/6] AUTHORITATIVE MOTHERSHIP ANCHORS' -ForegroundColor Yellow

    $anchors =
        [ordered]@{
            mothership_manifest =
                Join-Path $authoritative 'crates\vsa-mothership\Cargo.toml'

            autonomous_loop =
                Join-Path $authoritative 'crates\vsa-mothership\src\autonomous_mission_loop.rs'

            real_hyper_agent =
                Join-Path $authoritative 'crates\vsa-mothership\src\real_hyper_agent_runtime.rs'

            vertex_bridge =
                Join-Path $authoritative 'crates\vsa-vertex-bridge\Cargo.toml'

            workspace_manifest =
                Join-Path $authoritative 'Cargo.toml'
        }

    $anchorStatus =
        New-Object System.Collections.Generic.List[object]

    foreach ($entry in $anchors.GetEnumerator()) {
        $exists =
            Test-Path -LiteralPath $entry.Value

        $anchorStatus.Add(
            [pscustomobject]@{
                name = $entry.Key
                exists = $exists
                path = $entry.Value
            }
        )

        $color =
            if ($exists) { 'Green' } else { 'Red' }

        Write-Host `
            ("  {0,-24} {1}" -f $entry.Key, $(if ($exists) {'FOUND'} else {'MISSING'})) `
            -ForegroundColor $color
    }

    # ------------------------------------------------------------
    # 5. RANKED FIRING SOLUTION
    # ------------------------------------------------------------

    Write-Host ''
    Write-Host '[5/6] RANK FIRING SOLUTION' -ForegroundColor Yellow

    $best =
        $null

    if ($uiCandidates.Count -gt 0) {
        $best =
            $uiCandidates[0]
    }

    $status =
        'NO_UI_FOUND'

    $recommendation =
        'Bootstrap a new VSA Control Deck inside authoritative ProgramSource.'

    if ($best) {

        if ($best.score -ge 80) {
            $status =
                'UI_CANDIDATE_LOCKED'

            if ($best.inside_authoritative) {
                $recommendation =
                    'Dock editor/control surface directly into this authoritative UI.'
            }
            else {
                $recommendation =
                    'UI exists outside authoritative ProgramSource. Inspect and bridge deliberately; do not overwrite the Mothership workspace blindly.'
            }
        }
        elseif ($best.score -ge 50) {
            $status =
                'PARTIAL_UI_CANDIDATE'

            $recommendation =
                'Inspect the candidate before mutation; topology is not yet strong enough for automatic docking.'
        }
    }

    Write-Host "STATUS         : $status" -ForegroundColor Cyan

    if ($best) {
        Write-Host "BEST SCORE     : $($best.score)" -ForegroundColor Cyan
        Write-Host "BEST ROOT      : $($best.root)" -ForegroundColor Cyan
        Write-Host "BEST SIGNALS   : $($best.signals -join ', ')" -ForegroundColor Cyan
    }

    Write-Host "RECOMMENDATION : $recommendation" -ForegroundColor Cyan

    # ------------------------------------------------------------
    # 6. REPORT
    # ------------------------------------------------------------

    Write-Host ''
    Write-Host '[6/6] WRITE REPORT' -ForegroundColor Yellow

    $report =
        [ordered]@{
            schema =
                'vertex.cic.ui-editor-topology-recovery.v2'

            timestamp =
                (Get-Date).ToString('o')

            root =
                $root

            authoritative_program_source =
                $authoritative

            status =
                $status

            recommendation =
                $recommendation

            best_candidate =
                $best

            ui_candidates =
                @($uiCandidates | Select-Object -First 30)

            app_vue_files =
                @($appVueFiles | ForEach-Object { $_.FullName })

            tauri_manifests =
                @($tauriManifests | ForEach-Object { $_.FullName })

            symbol_hits =
                @($symbolHits | Select-Object -First 250)

            authoritative_anchors =
                @($anchorStatus)

            production_source_modified =
                $false
        }

    $report |
        ConvertTo-Json -Depth 12 |
        Set-Content `
            -LiteralPath $jsonPath `
            -Encoding UTF8

    $summary = @"
VERTEX — UI / EDITOR TOPOLOGY RECOVERY V2

STATUS:
$status

BEST CANDIDATE:
$(
    if ($best) {
        "$($best.root)`r`nScore: $($best.score)`r`nSignals: $($best.signals -join ', ')"
    } else {
        'NONE'
    }
)

RECOMMENDATION:
$recommendation

REPORT:
$jsonPath

PRODUCTION SOURCE:
UNTOUCHED
"@

    Set-Content `
        -LiteralPath $txtPath `
        -Value $summary `
        -Encoding UTF8

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' TOPOLOGY RECOVERY COMPLETE' -ForegroundColor Green
    Write-Host ' PRODUCTION SOURCE: UNTOUCHED' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host " JSON: $jsonPath" -ForegroundColor Green
    Write-Host " TEXT: $txtPath" -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
}
