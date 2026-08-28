& {
    $ErrorActionPreference = 'Stop'

    # ============================================================
    # VERTEX CIC — MONACO 0.56 EXPORT RECOVERY / V6 RE-FIRE
    # Windows PowerShell 5.1 compatible
    #
    # Confirmed runtime evidence:
    #   monaco-editor 0.56.0 cannot resolve:
    #     monaco-editor/min/vs/editor/editor.main.css
    #
    # Strategy:
    #   - keep current frontend baseline
    #   - derive V6 from V5
    #   - pin monaco-editor 0.55.1
    #   - static verify
    #   - re-fire
    #
    # V5 rollback already completed, so no production recovery
    # step is required here.
    # ============================================================

    $startup =
        'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'

    $base =
        Join-Path $startup 'VSA_Startup_Package_v0.2'

    $ui =
        Join-Path $base 'apps\vsa-shell'

    $core =
        Join-Path $base 'ProgramSource'

    $reports =
        Join-Path $core '_vertex_reports'

    $v5 =
        Join-Path $startup 'VERTEX_VSA_ULTIMATE_EDITOR_DOCKING_V5.ps1'

    $v6 =
        Join-Path $startup 'VERTEX_VSA_ULTIMATE_EDITOR_DOCKING_V6.ps1'

    $pkg =
        Join-Path $ui 'package.json'

    $viteEnv =
        Join-Path $ui 'src\vite-env.d.ts'

    $stamp =
        Get-Date -Format 'yyyyMMdd-HHmmss'

    $evidence =
        Join-Path $reports "MONACO_056_RECOVERY_V6.$stamp"

    $utf8Bom =
        New-Object System.Text.UTF8Encoding($true)

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' VERTEX — MONACO 0.56 EXPORT RECOVERY / V6 RE-FIRE' -ForegroundColor Cyan
    Write-Host ' PIN MONACO 0.55.1 / KEEP CURRENT VSA ARCHITECTURE' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan

    foreach ($required in @(
        $startup,
        $base,
        $ui,
        $core,
        $reports,
        $v5,
        $pkg,
        $viteEnv
    )) {
        if (-not (Test-Path -LiteralPath $required)) {
            throw "Required path missing: $required"
        }
    }

    $pnpm =
        Get-Command pnpm -ErrorAction SilentlyContinue

    if (-not $pnpm) {
        throw 'pnpm is required.'
    }

    New-Item `
        -ItemType Directory `
        -Path $evidence `
        -Force |
        Out-Null

    Write-Host ''
    Write-Host '[1/5] VERIFY CURRENT CLEAN FRONTEND BASELINE' -ForegroundColor Yellow

    Push-Location $ui

    try {
        & $pnpm.Source exec vue-tsc --noEmit

        if ($LASTEXITCODE -ne 0) {
            throw "Current typecheck baseline RED: $LASTEXITCODE"
        }

        & $pnpm.Source exec vite build

        if ($LASTEXITCODE -ne 0) {
            throw "Current Vite baseline RED: $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    Write-Host 'Current Typecheck: GREEN' -ForegroundColor Green
    Write-Host 'Current Vite Build: GREEN' -ForegroundColor Green

    Write-Host ''
    Write-Host '[2/5] SNAPSHOT CURRENT PACKAGE STATE' -ForegroundColor Yellow

    Copy-Item `
        -LiteralPath $pkg `
        -Destination (Join-Path $evidence 'package.before-v6.json') `
        -Force

    if (Test-Path -LiteralPath (Join-Path $ui 'pnpm-lock.yaml')) {
        Copy-Item `
            -LiteralPath (Join-Path $ui 'pnpm-lock.yaml') `
            -Destination (Join-Path $evidence 'pnpm-lock.before-v6.yaml') `
            -Force
    }

    Write-Host "Evidence: $evidence" -ForegroundColor Green

    Write-Host ''
    Write-Host '[3/5] DERIVE V6 FROM V5' -ForegroundColor Yellow

    $text =
        [IO.File]::ReadAllText($v5)

    if (-not $text.Contains("PmInstall 'monaco-editor@latest'")) {
        throw 'V5 Monaco install anchor not found.'
    }

    $text =
        $text.Replace(
            "PmInstall 'monaco-editor@latest'",
            "PmInstall 'monaco-editor@0.55.1'"
        )

    $text =
        $text.Replace(
            'VSA ULTIMATE EDITOR DOCKING V5',
            'VSA ULTIMATE EDITOR DOCKING V6'
        )

    $text =
        $text.Replace(
            'VSA_EDITOR_V5_BACKUP.',
            'VSA_EDITOR_V6_BACKUP.'
        )

    $text =
        $text.Replace(
            'VSA_EDITOR_V5_FAILED.',
            'VSA_EDITOR_V6_FAILED.'
        )

    $text =
        $text.Replace(
            'VSA_EDITOR_V5.',
            'VSA_EDITOR_V6.'
        )

    $text =
        $text.Replace(
            'V5 RED - DAMAGE CONTROL',
            'V6 RED - DAMAGE CONTROL'
        )

    [IO.File]::WriteAllText(
        $v6,
        $text,
        $utf8Bom
    )

    Unblock-File `
        -LiteralPath $v6 `
        -ErrorAction SilentlyContinue

    Write-Host "V6 created: $v6" -ForegroundColor Green

    Write-Host ''
    Write-Host '[4/5] STATIC V6 CHECK' -ForegroundColor Yellow

    $verify =
        [IO.File]::ReadAllText($v6)

    if (-not $verify.Contains("PmInstall 'monaco-editor@0.55.1'")) {
        throw 'Monaco 0.55.1 pin missing in V6.'
    }

    if ($verify.Contains("PmInstall 'monaco-editor@latest'")) {
        throw 'Unsafe Monaco latest install still present in V6.'
    }

    if (-not $verify.Contains("monaco-editor/min/vs/editor/editor.main.css")) {
        throw 'Expected Monaco CSS import missing.'
    }

    Write-Host 'Monaco version pin     : 0.55.1' -ForegroundColor Green
    Write-Host 'Existing CSS import    : PRESERVED' -ForegroundColor Green
    Write-Host 'Architecture           : UNCHANGED' -ForegroundColor Green
    Write-Host 'LEGACY                 : UNTOUCHED' -ForegroundColor Green

    Write-Host ''
    Write-Host '[5/5] RE-FIRE V6' -ForegroundColor Yellow

    & $v6

    if ($LASTEXITCODE -ne 0) {
        throw "V6 returned non-zero exit code: $LASTEXITCODE"
    }

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' VERTEX — MONACO RECOVERY / V6 RE-FIRE COMPLETE' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' Monaco 0.56 export break        AVOIDED' -ForegroundColor Green
    Write-Host ' Monaco 0.55.1                   PINNED' -ForegroundColor Green
    Write-Host ' Frontend baseline               GREEN' -ForegroundColor Green
    Write-Host " Evidence                        $evidence" -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
}
