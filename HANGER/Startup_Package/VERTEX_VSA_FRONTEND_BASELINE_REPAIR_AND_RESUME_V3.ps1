& {
    $ErrorActionPreference = 'Stop'

    # ============================================================
    # VERTEX CIC — VSA FRONTEND BASELINE REPAIR + V3 RESUME
    # Windows PowerShell 5.1 compatible
    #
    # Fix:
    #   vue-tsc 3.3.x + TypeScript 7.0.2 incompatibility
    #   -> pin TypeScript 6.0.2
    #
    # Then:
    #   verify frontend baseline
    #   -> resume original V3 docking strike
    #
    # RED:
    #   restore package.json + lockfile
    # ============================================================

    $ui =
        'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\apps\vsa-shell'

    $v3 =
        'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VERTEX_VSA_ULTIMATE_EDITOR_DOCKING_V3.ps1'

    $core =
        'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource'

    $reportDir =
        Join-Path $core '_vertex_reports'

    $stamp =
        Get-Date -Format 'yyyyMMdd-HHmmss'

    $backupDir =
        Join-Path $reportDir "VSA_FRONTEND_BASELINE_REPAIR.$stamp"

    $packageJson =
        Join-Path $ui 'package.json'

    $lockfile =
        Join-Path $ui 'pnpm-lock.yaml'

    $repairCommitted = $false

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' VERTEX — FRONTEND BASELINE REPAIR + V3 RESUME' -ForegroundColor Cyan
    Write-Host ' TypeScript 7 -> TypeScript 6 compatibility repair' -ForegroundColor Cyan
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

    if (-not $pnpm) {
        throw 'pnpm is required but was not found.'
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

    try {
        Write-Host ''
        Write-Host '[1/5] INSPECT CURRENT FRONTEND VERSIONS' -ForegroundColor Yellow

        Push-Location $ui

        try {
            & $pnpm.Source list typescript vue-tsc --depth 0
        }
        finally {
            Pop-Location
        }

        Write-Host ''
        Write-Host '[2/5] PIN COMPATIBLE TYPESCRIPT 6' -ForegroundColor Yellow

        Push-Location $ui

        try {
            & $pnpm.Source add `
                -D `
                'typescript@6.0.2' `
                'vue-tsc@3.3.11'

            if ($LASTEXITCODE -ne 0) {
                throw "pnpm dependency repair failed. ExitCode=$LASTEXITCODE"
            }
        }
        finally {
            Pop-Location
        }

        Write-Host ''
        Write-Host '[3/5] VERIFY DEPENDENCY GRAPH' -ForegroundColor Yellow

        Push-Location $ui

        try {
            & $pnpm.Source list typescript vue-tsc --depth 0

            if ($LASTEXITCODE -ne 0) {
                throw "dependency verification failed. ExitCode=$LASTEXITCODE"
            }

            $typescriptVersion =
                & node -p "require('./node_modules/typescript/package.json').version"

            $vueTscVersion =
                & node -p "require('./node_modules/vue-tsc/package.json').version"

            Write-Host "TypeScript : $typescriptVersion" -ForegroundColor Green
            Write-Host "vue-tsc    : $vueTscVersion" -ForegroundColor Green

            if ($typescriptVersion.Trim() -ne '6.0.2') {
                throw "TypeScript pin did not take effect: $typescriptVersion"
            }
        }
        finally {
            Pop-Location
        }

        Write-Host ''
        Write-Host '[4/5] FRONTEND BASELINE RETEST' -ForegroundColor Yellow

        Push-Location $ui

        try {
            & $pnpm.Source build

            if ($LASTEXITCODE -ne 0) {
                throw "frontend baseline still RED. ExitCode=$LASTEXITCODE"
            }
        }
        finally {
            Pop-Location
        }

        Write-Host ''
        Write-Host 'FRONTEND BASELINE: GREEN' -ForegroundColor Green
        Write-Host 'TypeScript 6 compatibility: LOCKED' -ForegroundColor Green
        $repairCommitted = $true

        Write-Host ''
        Write-Host '[5/5] RESUME V3 DOCKING MISSION' -ForegroundColor Yellow

        & $v3

        if ($LASTEXITCODE -ne 0) {
            throw "V3 docking strike returned non-zero exit code: $LASTEXITCODE"
        }

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor Green
        Write-Host ' VERTEX — BASELINE REPAIRED / V3 RESUMED' -ForegroundColor Green
        Write-Host '============================================================' -ForegroundColor Green
        Write-Host " Backup: $backupDir" -ForegroundColor Green
        Write-Host '============================================================' -ForegroundColor Green
    }
    catch {
        Write-Host ''
        Write-Host '============================================================' -ForegroundColor Red
        Write-Host ' FRONTEND REPAIR RED — ROLLBACK' -ForegroundColor Red
        Write-Host '============================================================' -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        if (-not $repairCommitted) {
            Copy-Item `
                -LiteralPath (Join-Path $backupDir 'package.json') `
                -Destination $packageJson `
                -Force

            if (
                (Test-Path -LiteralPath (Join-Path $backupDir 'pnpm-lock.yaml')) -and
                (Test-Path -LiteralPath $lockfile)
            ) {
                Copy-Item `
                    -LiteralPath (Join-Path $backupDir 'pnpm-lock.yaml') `
                    -Destination $lockfile `
                    -Force
            }

            Write-Host 'Frontend dependency repair: ROLLED BACK' -ForegroundColor Yellow
            Write-Host 'node_modules may keep cached packages; package/lock state restored.' -ForegroundColor DarkYellow
        }
        else {
            Write-Host 'Frontend dependency repair: RETAINED (already GREEN)' -ForegroundColor Green
            Write-Host 'Only the downstream V3 failure remains to diagnose.' -ForegroundColor Yellow
        }

        Write-Host "Evidence backup: $backupDir" -ForegroundColor Yellow

        throw
    }
}
