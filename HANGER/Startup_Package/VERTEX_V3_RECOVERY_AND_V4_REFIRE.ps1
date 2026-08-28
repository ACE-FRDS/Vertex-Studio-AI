& {
    $ErrorActionPreference = 'Stop'

    # ============================================================
    # VERTEX CIC — V3 RECOVERY / V4 RE-FIRE
    # Windows PowerShell 5.1 compatible
    #
    # Repairs confirmed by execution evidence:
    #   1. Recover partial V3 state from latest V3 backup.
    #   2. Keep/restore frontend GREEN baseline:
    #        TypeScript 6.0.2 + vue-tsc 3.3.11 + vite-env.d.ts
    #   3. Derive V4 from V3:
    #        - R() rollback helper -> Restore-BackupFile()
    #        - generate required src-tauri/icons/icon.ico
    #   4. Re-fire V4.
    #
    # No LEGACY access.
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

    $v3 =
        Join-Path $startup 'VERTEX_VSA_ULTIMATE_EDITOR_DOCKING_V3.ps1'

    $v4 =
        Join-Path $startup 'VERTEX_VSA_ULTIMATE_EDITOR_DOCKING_V4.ps1'

    $pkg =
        Join-Path $ui 'package.json'

    $lock =
        Join-Path $ui 'pnpm-lock.yaml'

    $app =
        Join-Path $ui 'src\App.vue'

    $main =
        Join-Path $ui 'src\main.ts'

    $viteEnv =
        Join-Path $ui 'src\vite-env.d.ts'

    $tauri =
        Join-Path $ui 'src-tauri'

    $editor =
        Join-Path $ui 'src\vertex-editor'

    $stamp =
        Get-Date -Format 'yyyyMMdd-HHmmss'

    $evidence =
        Join-Path $reports "V3_RECOVERY_V4_REFIRE.$stamp"

    $utf8 =
        New-Object System.Text.UTF8Encoding($false)

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' VERTEX — V3 RECOVERY / V4 RE-FIRE' -ForegroundColor Cyan
    Write-Host ' ICON RESOURCE + POWERSHELL ROLLBACK COLLISION REPAIR' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan

    foreach ($required in @(
        $startup,
        $base,
        $ui,
        $core,
        $reports,
        $v3,
        $pkg,
        $app,
        $main
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
    Write-Host '[1/7] PRESERVE CURRENT PARTIAL-STATE EVIDENCE' -ForegroundColor Yellow

    foreach ($file in @(
        $pkg,
        $lock,
        $app,
        $main,
        $viteEnv
    )) {
        if (Test-Path -LiteralPath $file) {
            Copy-Item `
                -LiteralPath $file `
                -Destination (Join-Path $evidence ([IO.Path]::GetFileName($file))) `
                -Force
        }
    }

    if (Test-Path -LiteralPath $tauri) {
        $smallTauri =
            Join-Path $evidence 'src-tauri-current'

        New-Item `
            -ItemType Directory `
            -Path $smallTauri `
            -Force |
            Out-Null

        foreach ($relative in @(
            'Cargo.toml',
            'Cargo.lock',
            'build.rs',
            'tauri.conf.json',
            'src\main.rs',
            'src\lib.rs',
            'capabilities\default.json',
            'icons\icon.ico'
        )) {
            $source =
                Join-Path $tauri $relative

            if (Test-Path -LiteralPath $source) {
                $dest =
                    Join-Path $smallTauri $relative

                $destParent =
                    Split-Path -Parent $dest

                if ($destParent) {
                    New-Item `
                        -ItemType Directory `
                        -Path $destParent `
                        -Force |
                        Out-Null
                }

                Copy-Item `
                    -LiteralPath $source `
                    -Destination $dest `
                    -Force
            }
        }
    }

    Write-Host "Evidence: $evidence" -ForegroundColor Green

    Write-Host ''
    Write-Host '[2/7] FIND LATEST V3 PRE-CONSTRUCTION BACKUP' -ForegroundColor Yellow

    $latestBackup =
        Get-ChildItem `
            -LiteralPath $reports `
            -Directory `
            -Filter 'VSA_EDITOR_V3_BACKUP.*' `
            -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latestBackup) {
        throw 'No VSA_EDITOR_V3_BACKUP.* directory found.'
    }

    Write-Host "Backup: $($latestBackup.FullName)" -ForegroundColor Green

    $restoreMap =
        [ordered]@{
            'apps__vsa-shell__package.json' =
                $pkg

            'apps__vsa-shell__pnpm-lock.yaml' =
                $lock

            'apps__vsa-shell__src__App.vue' =
                $app

            'apps__vsa-shell__src__main.ts' =
                $main
        }

    Write-Host ''
    Write-Host '[3/7] RESTORE CLEAN V3 BASELINE' -ForegroundColor Yellow

    foreach ($entry in $restoreMap.GetEnumerator()) {
        $source =
            Join-Path $latestBackup.FullName $entry.Key

        if (Test-Path -LiteralPath $source) {
            Copy-Item `
                -LiteralPath $source `
                -Destination $entry.Value `
                -Force

            Write-Host "Restored: $($entry.Value)" -ForegroundColor Green
        }
        elseif ($entry.Key -eq 'apps__vsa-shell__pnpm-lock.yaml') {
            Write-Host 'Backup had no pnpm-lock.yaml; continuing.' -ForegroundColor DarkYellow
        }
        else {
            throw "Expected V3 backup member missing: $source"
        }
    }

    if (Test-Path -LiteralPath $tauri) {
        Remove-Item `
            -LiteralPath $tauri `
            -Recurse `
            -Force
    }

    if (Test-Path -LiteralPath $editor) {
        Remove-Item `
            -LiteralPath $editor `
            -Recurse `
            -Force
    }

    Write-Host 'Partial src-tauri / vertex-editor: CLEARED' -ForegroundColor Green

    Write-Host ''
    Write-Host '[4/7] RE-LOCK FRONTEND GREEN BASELINE' -ForegroundColor Yellow

    Push-Location $ui

    try {
        & $pnpm.Source add `
            -D `
            'typescript@6.0.2' `
            'vue-tsc@3.3.11'

        if ($LASTEXITCODE -ne 0) {
            throw "TypeScript/vue-tsc pin failed: $LASTEXITCODE"
        }

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
            $utf8
        )

        & $pnpm.Source install

        if ($LASTEXITCODE -ne 0) {
            throw "pnpm install failed: $LASTEXITCODE"
        }

        & $pnpm.Source exec vue-tsc --noEmit

        if ($LASTEXITCODE -ne 0) {
            throw "vue-tsc baseline RED: $LASTEXITCODE"
        }

        & $pnpm.Source exec vite build

        if ($LASTEXITCODE -ne 0) {
            throw "vite baseline RED: $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    Write-Host 'Frontend Typecheck: GREEN' -ForegroundColor Green
    Write-Host 'Frontend Build    : GREEN' -ForegroundColor Green

    Write-Host ''
    Write-Host '[5/7] DERIVE V4 FROM V3' -ForegroundColor Yellow

    $v3Text =
        [IO.File]::ReadAllText($v3)

    $oldFunction =
        'function R([string]$p){'

    $newFunction =
        'function Restore-BackupFile([string]$p){'

    if (-not $v3Text.Contains($oldFunction)) {
        throw 'V3 rollback helper anchor not found.'
    }

    $v4Text =
        $v3Text.Replace(
            $oldFunction,
            $newFunction
        )

    $oldCall =
        'if($p){R $p}'

    $newCall =
        'if($p){Restore-BackupFile $p}'

    if (-not $v4Text.Contains($oldCall)) {
        throw 'V3 rollback call anchor not found.'
    }

    $v4Text =
        $v4Text.Replace(
            $oldCall,
            $newCall
        )

    $iconAnchor =
        '$created+=@($tc,$tb,$tm,$tconf,$tcap)'

    if (-not $v4Text.Contains($iconAnchor)) {
        throw 'V3 Tauri icon insertion anchor not found.'
    }

    $iconBase64 =
        'AAABAAEAICAAAAEAIABfAQAAFgAAAIlQTkcNChoKAAAADUlIRFIAAAAgAAAAIAgGAAAAc3p69AAAASZJREFUeJztV7EVgjAQ/fhcwIJnrw3QuQB7pHcBB7BiABewzx4uQCc0TsAQWoV3BIS7EInv6a9CSO7+/dzdS6LNdvdEQKxCOgeAtRkcT49FHV8vewDfpICBYfYp2EoHV+BPoJcDFHV1b8dJmomNc/aPKuDiVGqHfQQ0Gp/rJwm4qqAazdovSsLD7SxaZ0jMJpCkWWtsigT9X+aFHwIAoGM16ITO0Xm6fgyjZUiRpBnq6t5TosyLQcfc3BE3Ih2rt2pwo3YmQKOyz5d+SyrHuRXbecCtkNkEVKM75UUjV40W9w3nPkBzwc4JiRpsAlP1rWPVmeeSYBMwxm3nds+XkhAdwVimD1WI104oBcc5IOiEQ/BxXwh+JQtOoHcES7+QgisQ/fzr+AWu9GjhayhCCgAAAABJRU5ErkJggg=='

    $iconBlock = @"
  `$iconDir=Join-Path `$tauri 'icons'
  `$icon=Join-Path `$iconDir 'icon.ico'
  New-Item -ItemType Directory -Path `$iconDir -Force|Out-Null
  [IO.File]::WriteAllBytes(`$icon,[Convert]::FromBase64String('$iconBase64'))
  if(-not(Test-Path -LiteralPath `$icon)){throw 'Tauri Windows icon generation failed'}
  Write-Host "Tauri Windows icon: `$icon" -ForegroundColor Green
  `$created+=@(`$tc,`$tb,`$tm,`$tconf,`$tcap,`$icon)
"@

    $v4Text =
        $v4Text.Replace(
            $iconAnchor,
            $iconBlock.TrimEnd()
        )

    $v4Text =
        $v4Text.Replace(
            'VSA ULTIMATE EDITOR DOCKING V3',
            'VSA ULTIMATE EDITOR DOCKING V4'
        )

    $v4Text =
        $v4Text.Replace(
            'VSA_EDITOR_V3_BACKUP.',
            'VSA_EDITOR_V4_BACKUP.'
        )

    $v4Text =
        $v4Text.Replace(
            'VSA_EDITOR_V3_FAILED.',
            'VSA_EDITOR_V4_FAILED.'
        )

    $v4Text =
        $v4Text.Replace(
            'VSA_EDITOR_V3.',
            'VSA_EDITOR_V4.'
        )

    $v4Text =
        $v4Text.Replace(
            'V3 RED — DAMAGE CONTROL',
            'V4 RED — DAMAGE CONTROL'
        )

    [IO.File]::WriteAllText(
        $v4,
        $v4Text,
        $utf8
    )

    Unblock-File `
        -LiteralPath $v4 `
        -ErrorAction SilentlyContinue

    Write-Host "V4 created: $v4" -ForegroundColor Green

    Write-Host ''
    Write-Host '[6/7] STATIC V4 SAFETY CHECK' -ForegroundColor Yellow

    $verify =
        [IO.File]::ReadAllText($v4)

    foreach ($must in @(
        'function Restore-BackupFile([string]$p){',
        'Restore-BackupFile $p',
        "Join-Path `$tauri 'icons'",
        "[IO.File]::WriteAllBytes(`$icon",
        'icon.ico'
    )) {
        if (-not $verify.Contains($must)) {
            throw "V4 static verification missing: $must"
        }
    }

    if ($verify.Contains('function R([string]$p){')) {
        throw 'Unsafe PowerShell R() helper still present in V4.'
    }

    Write-Host 'Rollback helper collision: FIXED' -ForegroundColor Green
    Write-Host 'Windows icon generation     : INSTALLED' -ForegroundColor Green

    Write-Host ''
    Write-Host '[7/7] RE-FIRE V4' -ForegroundColor Yellow

    & $v4

    if ($LASTEXITCODE -ne 0) {
        throw "V4 returned non-zero exit code: $LASTEXITCODE"
    }

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' VERTEX — V3 RECOVERY / V4 RE-FIRE COMPLETE' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' Frontend baseline              GREEN' -ForegroundColor Green
    Write-Host ' PowerShell rollback collision  FIXED' -ForegroundColor Green
    Write-Host ' Tauri Windows icon             INSTALLED' -ForegroundColor Green
    Write-Host " Evidence                       $evidence" -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
}
