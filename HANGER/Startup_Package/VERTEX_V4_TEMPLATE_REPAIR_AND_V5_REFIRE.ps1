& {
    $ErrorActionPreference = 'Stop'

    # ============================================================
    # VERTEX CIC — V4 TEMPLATE REPAIR / V5 RE-FIRE
    # Windows PowerShell 5.1 compatible
    #
    # Evidence-driven repairs:
    #   - Tauri Rust compile is already GREEN.
    #   - Vue SFC parser stopped on VertexEditorDock.vue.
    #   - Remove non-void self-closing HTML ambiguity.
    #   - Remove non-ASCII UI glyphs from generated template.
    #   - Write V5 PowerShell with UTF-8 BOM for PS 5.1.
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

    $v4 =
        Join-Path $startup 'VERTEX_VSA_ULTIMATE_EDITOR_DOCKING_V4.ps1'

    $v3 =
        Join-Path $startup 'VERTEX_VSA_ULTIMATE_EDITOR_DOCKING_V3.ps1'

    $v5 =
        Join-Path $startup 'VERTEX_VSA_ULTIMATE_EDITOR_DOCKING_V5.ps1'

    $stamp =
        Get-Date -Format 'yyyyMMdd-HHmmss'

    $evidence =
        Join-Path $reports "V4_TEMPLATE_REPAIR_V5_REFIRE.$stamp"

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' VERTEX — V4 TEMPLATE REPAIR / V5 RE-FIRE' -ForegroundColor Cyan
    Write-Host ' VUE SFC STRUCTURE + PS5.1 UTF-8 HARDENING' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan

    foreach ($required in @(
        $startup,
        $base,
        $ui,
        $core,
        $reports
    )) {
        if (-not (Test-Path -LiteralPath $required)) {
            throw "Required path missing: $required"
        }
    }

    $source =
        if (Test-Path -LiteralPath $v4) {
            $v4
        }
        elseif (Test-Path -LiteralPath $v3) {
            $v3
        }
        else {
            throw 'Neither V4 nor V3 docking source exists.'
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
    Write-Host '[1/6] VERIFY CLEAN FRONTEND BASELINE' -ForegroundColor Yellow

    Push-Location $ui

    try {
        & $pnpm.Source add `
            -D `
            'typescript@6.0.2' `
            'vue-tsc@3.3.11'

        if ($LASTEXITCODE -ne 0) {
            throw "TypeScript/vue-tsc baseline lock failed: $LASTEXITCODE"
        }

        $viteEnv =
            Join-Path $ui 'src\vite-env.d.ts'

        $viteEnvText = @'
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
            $viteEnvText,
            (New-Object System.Text.UTF8Encoding($false))
        )

        & $pnpm.Source exec vue-tsc --noEmit

        if ($LASTEXITCODE -ne 0) {
            throw "Current clean baseline typecheck RED: $LASTEXITCODE"
        }

        & $pnpm.Source exec vite build

        if ($LASTEXITCODE -ne 0) {
            throw "Current clean baseline build RED: $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    Write-Host 'Current frontend baseline: GREEN' -ForegroundColor Green

    Write-Host ''
    Write-Host '[2/6] LOAD DOCKING SOURCE AS UTF-8' -ForegroundColor Yellow

    $sourceText =
        [IO.File]::ReadAllText(
            $source,
            [Text.Encoding]::UTF8
        )

    Copy-Item `
        -LiteralPath $source `
        -Destination (Join-Path $evidence ([IO.Path]::GetFileName($source))) `
        -Force

    Write-Host "Source: $source" -ForegroundColor Green

    Write-Host ''
    Write-Host '[3/6] APPLY VUE TEMPLATE HARDENING' -ForegroundColor Yellow

    $patched =
        $sourceText

    # Version/report labels.
    $patched =
        $patched.Replace(
            'VSA ULTIMATE EDITOR DOCKING V4',
            'VSA ULTIMATE EDITOR DOCKING V5'
        )

    $patched =
        $patched.Replace(
            'VSA ULTIMATE EDITOR DOCKING V3',
            'VSA ULTIMATE EDITOR DOCKING V5'
        )

    $patched =
        $patched.Replace(
            'VSA_EDITOR_V4_BACKUP.',
            'VSA_EDITOR_V5_BACKUP.'
        )

    $patched =
        $patched.Replace(
            'VSA_EDITOR_V4_FAILED.',
            'VSA_EDITOR_V5_FAILED.'
        )

    $patched =
        $patched.Replace(
            'VSA_EDITOR_V4.',
            'VSA_EDITOR_V5.'
        )

    $patched =
        $patched.Replace(
            'VSA_EDITOR_V3_BACKUP.',
            'VSA_EDITOR_V5_BACKUP.'
        )

    $patched =
        $patched.Replace(
            'VSA_EDITOR_V3_FAILED.',
            'VSA_EDITOR_V5_FAILED.'
        )

    $patched =
        $patched.Replace(
            'VSA_EDITOR_V3.',
            'VSA_EDITOR_V5.'
        )

    $patched =
        $patched.Replace(
            'V4 RED — DAMAGE CONTROL',
            'V5 RED - DAMAGE CONTROL'
        )

    $patched =
        $patched.Replace(
            'V3 RED — DAMAGE CONTROL',
            'V5 RED - DAMAGE CONTROL'
        )

    # Explicitly close non-void HTML tags in Vue SFC.
    $patched =
        $patched.Replace(
            '<i/>VSA EDITOR',
            '<i></i>VSA EDITOR'
        )

    $patched =
        $patched.Replace(
            '<span class="grow"/>',
            '<span class="grow"></span>'
        )

    $patched =
        $patched.Replace(
            '<div ref="host" class="editor"/>',
            '<div ref="host" class="editor"></div>'
        )

    $patched =
        $patched.Replace(
            '<span/><i v-if="dirty">',
            '<span></span><i v-if="dirty">'
        )

    # ASCII-only UI glyphs for Windows PowerShell 5.1 source safety.
    $patched =
        $patched.Replace('×', 'X')

    $patched =
        $patched.Replace('·', '-')

    $patched =
        $patched.Replace('▸', '>')

    $patched =
        $patched.Replace('•', '*')

    $patched =
        $patched.Replace('—', '-')

    $patched =
        $patched.Replace('–', '-')

    # If deriving from old V3 directly, ensure rollback helper does not
    # collide with PowerShell alias R = Invoke-History.
    if ($patched.Contains('function R([string]$p){')) {
        $patched =
            $patched.Replace(
                'function R([string]$p){',
                'function Restore-BackupFile([string]$p){'
            )
    }

    if ($patched.Contains('if($p){R $p}')) {
        $patched =
            $patched.Replace(
                'if($p){R $p}',
                'if($p){Restore-BackupFile $p}'
            )
    }

    # If V4 icon generation is absent, stop instead of regressing.
    if (
        -not $patched.Contains('icon.ico') -or
        -not $patched.Contains('WriteAllBytes')
    ) {
        throw 'Windows icon generation contract missing from docking source.'
    }

    Write-Host 'Non-void self-closing tags: EXPLICITLY CLOSED' -ForegroundColor Green
    Write-Host 'Template UI glyphs        : ASCII HARDENED' -ForegroundColor Green
    Write-Host 'Rollback helper           : SAFE' -ForegroundColor Green

    Write-Host ''
    Write-Host '[4/6] WRITE V5 WITH UTF-8 BOM' -ForegroundColor Yellow

    $utf8Bom =
        New-Object System.Text.UTF8Encoding($true)

    [IO.File]::WriteAllText(
        $v5,
        $patched,
        $utf8Bom
    )

    Unblock-File `
        -LiteralPath $v5 `
        -ErrorAction SilentlyContinue

    $bytes =
        [IO.File]::ReadAllBytes($v5)

    if (
        $bytes.Length -lt 3 -or
        $bytes[0] -ne 0xEF -or
        $bytes[1] -ne 0xBB -or
        $bytes[2] -ne 0xBF
    ) {
        throw 'V5 UTF-8 BOM verification failed.'
    }

    Write-Host "V5: $v5" -ForegroundColor Green
    Write-Host 'UTF-8 BOM: VERIFIED' -ForegroundColor Green

    Write-Host ''
    Write-Host '[5/6] STATIC TEMPLATE SAFETY CHECK' -ForegroundColor Yellow

    $verify =
        [IO.File]::ReadAllText(
            $v5,
            [Text.Encoding]::UTF8
        )

    foreach ($bad in @(
        '<i/>VSA EDITOR',
        '<span class="grow"/>',
        '<div ref="host" class="editor"/>',
        '<span/><i v-if="dirty">',
        'function R([string]$p){'
    )) {
        if ($verify.Contains($bad)) {
            throw "Unsafe V5 token still present: $bad"
        }
    }

    foreach ($must in @(
        '<i></i>VSA EDITOR',
        '<span class="grow"></span>',
        '<div ref="host" class="editor"></div>',
        '<span></span><i v-if="dirty">',
        'Restore-BackupFile $p',
        'icon.ico'
    )) {
        if (-not $verify.Contains($must)) {
            throw "Required V5 repair token missing: $must"
        }
    }

    Write-Host 'Static V5 verification: GREEN' -ForegroundColor Green

    Write-Host ''
    Write-Host '[6/6] RE-FIRE V5' -ForegroundColor Yellow

    & $v5

    if ($LASTEXITCODE -ne 0) {
        throw "V5 returned non-zero exit code: $LASTEXITCODE"
    }

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' VERTEX — V5 RE-FIRE COMPLETE' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' Vue template structure      HARDENED' -ForegroundColor Green
    Write-Host ' PowerShell UTF-8 source     BOM VERIFIED' -ForegroundColor Green
    Write-Host ' Windows resource icon       RETAINED' -ForegroundColor Green
    Write-Host ' Rollback helper             SAFE' -ForegroundColor Green
    Write-Host " Evidence                    $evidence" -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
}
