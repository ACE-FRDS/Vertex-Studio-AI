& {
    $ErrorActionPreference = 'Stop'

    # ============================================================
    # VERTEX CIC — VSA FRONTEND BASELINE REPAIR V2 + V3 RESUME
    # Windows PowerShell 5.1 compatible
    #
    # Fixes:
    #   1) vue-tsc 3.3.11 + TS7 incompatibility -> pin TS 6.0.2
    #   2) CSS side-effect import typing -> add src/vite-env.d.ts
    #
    # Then:
    #   vue-tsc --noEmit
    #   vite build
    #   resume V3 docking
    #
    # Fail-closed:
    #   frontend repair RED -> restore package/lock/vite-env state
    #   V3 RED after frontend GREEN -> keep frontend repair
    # ============================================================

    $ui =
        'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\apps\vsa-shell'

    $core =
        'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource'

    $v3 =
        'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VERTEX_VSA_ULTIMATE_EDITOR_DOCKING_V3.ps1'

    $packageJson =
        Join-Path $ui 'package.json'

    $lockfile =
        Join-Path $ui 'pnpm-lock.yaml'

    $viteEnv =
        Join-Path $ui 'src\vite-env.d.ts'

    $reportDir =
        Join-Path $core '_vertex_reports'

    $stamp =
        Get-Date -Format 'yyyyMMdd-HHmmss'

    $backupDir =
        Join-Path $reportDir "VSA_FRONTEND_BASELINE_REPAIR_V2.$stamp"

    $repairCommitted = $false

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' VERTEX — FRONTEND BASELINE REPAIR V2 + V3 RESUME' -ForegroundColor Cyan
    Write-Host ' TS6 PIN + VITE/CSS TYPE DECLARATION' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan

    foreach ($required in @(
        $ui,
        $core,
        $packageJson,
        $v3
    )) {
        if (-not (Test-Path -LiteralPath $required)) {
            throw "Required path missing: $required"
        }
    }

    $pnpm =
        Get-Command pnpm -ErrorAction SilentlyContinue

    $node =
        Get-Command node -ErrorAction SilentlyContinue

    if (-not $pnpm) {
        throw 'pnpm is required but was not found.'
    }

    if (-not $node) {
        throw 'node is required but was not found.'
    }

    New-Item `
        -ItemType Directory `
        -Path $reportDir `
        -Force |
        Out-Null

    New-Item `
        -ItemType Directory `
        -Path $backupDir `
        -Force |
        Out-Null

    Copy-Item `
        -LiteralPath $packageJson `
        -Destination (Join-Path $backupDir 'package.json') `
        -Force

    if (Test-Path -LiteralPath $lockfile) {
        Copy-Item `
            -LiteralPath $lockfile `
            -Destination (Join-Path $backupDir 'pnpm-lock.yaml') `
            -Force
    }

    $viteEnvOriginallyExisted =
        Test-Path -LiteralPath $viteEnv

    if ($viteEnvOriginallyExisted) {
        Copy-Item `
            -LiteralPath $viteEnv `
            -Destination (Join-Path $backupDir 'vite-env.d.ts') `
            -Force
    }

    try {
        Write-Host ''
        Write-Host '[1/6] PIN TYPESCRIPT 6 + vue-tsc' -ForegroundColor Yellow

        Push-Location $ui

        try {
            & $pnpm.Source add `
                -D `
                'typescript@6.0.2' `
                'vue-tsc@3.3.11'

            if ($LASTEXITCODE -ne 0) {
                throw "dependency repair failed. ExitCode=$LASTEXITCODE"
            }
        }
        finally {
            Pop-Location
        }

        Write-Host ''
        Write-Host '[2/6] INSTALL VITE / CSS TYPE DECLARATION' -ForegroundColor Yellow

        $viteEnvContent = @'
/// <reference types="vite/client" />

declare module '*.css' {}
declare module '*.scss' {}
declare module '*.sass' {}
declare module '*.less' {}
declare module '*.styl' {}
declare module '*.stylus' {}
'@

        [IO.File]::WriteAllText(
            $viteEnv,
            $viteEnvContent,
            (New-Object System.Text.UTF8Encoding($false))
        )

        Write-Host "Type declaration: $viteEnv" -ForegroundColor Green

        Write-Host ''
        Write-Host '[3/6] VERIFY DEPENDENCY GRAPH' -ForegroundColor Yellow

        Push-Location $ui

        try {
            & $pnpm.Source list typescript vue-tsc --depth 0

            if ($LASTEXITCODE -ne 0) {
                throw "dependency verification failed. ExitCode=$LASTEXITCODE"
            }

            $typescriptVersion =
                (& $node.Source -p "require('./node_modules/typescript/package.json').version").Trim()

            $vueTscVersion =
                (& $node.Source -p "require('./node_modules/vue-tsc/package.json').version").Trim()

            Write-Host "TypeScript : $typescriptVersion" -ForegroundColor Green
            Write-Host "vue-tsc    : $vueTscVersion" -ForegroundColor Green

            if ($typescriptVersion -ne '6.0.2') {
                throw "TypeScript pin failed: $typescriptVersion"
            }

            if ($vueTscVersion -ne '3.3.11') {
                throw "vue-tsc pin failed: $vueTscVersion"
            }
        }
        finally {
            Pop-Location
        }

        Write-Host ''
        Write-Host '[4/6] TYPECHECK GATE' -ForegroundColor Yellow

        Push-Location $ui

        try {
            & $pnpm.Source exec vue-tsc --noEmit

            if ($LASTEXITCODE -ne 0) {
                throw "vue-tsc typecheck still RED. ExitCode=$LASTEXITCODE"
            }
        }
        finally {
            Pop-Location
        }

        Write-Host 'vue-tsc: GREEN' -ForegroundColor Green

        Write-Host ''
        Write-Host '[5/6] VITE PRODUCTION BUILD GATE' -ForegroundColor Yellow

        Push-Location $ui

        try {
            & $pnpm.Source exec vite build

            if ($LASTEXITCODE -ne 0) {
                throw "vite production build still RED. ExitCode=$LASTEXITCODE"
            }
        }
        finally {
            Pop-Location
        }

        Write-Host 'vite build: GREEN' -ForegroundColor Green
        Write-Host 'FRONTEND BASELINE: GREEN' -ForegroundColor Green

        $repairCommitted = $true

        Write-Host ''
        Write-Host '[6/6] RESUME V3 DOCKING' -ForegroundColor Yellow

        & $v3

        if ($LASTEXITCODE -ne 0) {
            throw "V3 docking returned non-zero exit code: $LASTEXITCODE"
        }

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor Green
        Write-Host ' FRONTEND BASELINE GREEN / V3 RESUMED' -ForegroundColor Green
        Write-Host '============================================================' -ForegroundColor Green
        Write-Host ' TypeScript 6.0.2                  LOCKED' -ForegroundColor Green
        Write-Host ' vue-tsc 3.3.11                    LOCKED' -ForegroundColor Green
        Write-Host ' vite/client declaration           ONLINE' -ForegroundColor Green
        Write-Host ' CSS side-effect imports           TYPED' -ForegroundColor Green
        Write-Host " Backup: $backupDir" -ForegroundColor Green
        Write-Host '============================================================' -ForegroundColor Green
    }
    catch {
        Write-Host ''
        Write-Host '============================================================' -ForegroundColor Red
        Write-Host ' FRONTEND REPAIR V2 RED — DAMAGE CONTROL' -ForegroundColor Red
        Write-Host '============================================================' -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        if (-not $repairCommitted) {
            Copy-Item `
                -LiteralPath (Join-Path $backupDir 'package.json') `
                -Destination $packageJson `
                -Force

            if (Test-Path -LiteralPath (Join-Path $backupDir 'pnpm-lock.yaml')) {
                Copy-Item `
                    -LiteralPath (Join-Path $backupDir 'pnpm-lock.yaml') `
                    -Destination $lockfile `
                    -Force
            }

            if ($viteEnvOriginallyExisted) {
                Copy-Item `
                    -LiteralPath (Join-Path $backupDir 'vite-env.d.ts') `
                    -Destination $viteEnv `
                    -Force
            }
            elseif (Test-Path -LiteralPath $viteEnv) {
                Remove-Item `
                    -LiteralPath $viteEnv `
                    -Force
            }

            Write-Host 'Frontend dependency/type repair: ROLLED BACK' -ForegroundColor Yellow
        }
        else {
            Write-Host 'Frontend repair already GREEN: RETAINED' -ForegroundColor Green
            Write-Host 'Only downstream V3 failure remains.' -ForegroundColor Yellow
        }

        Write-Host "Evidence: $backupDir" -ForegroundColor Yellow
        throw
    }
}
