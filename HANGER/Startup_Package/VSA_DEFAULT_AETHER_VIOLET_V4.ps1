& {
$ErrorActionPreference='Stop'

# ============================================================
# VERTEX - DEFAULT AETHER VIOLET V4
#
# Mission:
#   Replace VSA default cockpit skin with a slightly violet,
#   fantastical "Aether" visual system while preserving:
#   - 27-inch readability
#   - docking architecture
#   - editor / preview / Hub
#   - real telemetry
#   - Mothership / Runtime Bus
#
# Visual doctrine:
#   deep navy-black + indigo-violet + ice cyan + restrained green
#   fantasy atmosphere WITHOUT sacrificing developer readability.
#
# No mock. This patches the real desktop shell.
# ============================================================

$startup='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$base=Join-Path $startup 'VSA_Startup_Package_v0.2'
$ui=Join-Path $base 'apps\vsa-shell'
$core=Join-Path $base 'ProgramSource'
$reports=Join-Path $core '_vertex_reports'
$cockpit=Join-Path $ui 'src\vertex-cockpit'
$panels=Join-Path $cockpit 'panels'
$shell=Join-Path $cockpit 'VertexCockpitShell.vue'
$frame=Join-Path $panels 'CockpitPanelFrame.vue'
$status=Join-Path $panels 'CockpitStatusBar.vue'
$editor=Join-Path $ui 'src\vertex-editor\VertexEditorDock.vue'
$themeDir=Join-Path $cockpit 'theme'
$themeCss=Join-Path $themeDir 'vertex-aether-violet.css'
$packageJson=Join-Path $ui 'package.json'
$coreCargo=Join-Path $core 'Cargo.toml'
$tauriCargo=Join-Path $ui 'src-tauri\Cargo.toml'
$tauriCheckTarget=Join-Path $startup '_build\VSA_TAURI_AETHER_V4_CHECK'

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $reports "VSA_DEFAULT_AETHER_VIOLET_V4_BACKUP.$stamp"
$failed=Join-Path $reports "VSA_DEFAULT_AETHER_VIOLET_V4_FAILED.$stamp"
$report=Join-Path $reports "VSA_DEFAULT_AETHER_VIOLET_V4.$stamp.json"

$utf8=New-Object System.Text.UTF8Encoding($false)

function WriteUtf8([string]$Path,[string]$Content){
  $parent=Split-Path -Parent $Path
  if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
  [IO.File]::WriteAllText($Path,$Content,$utf8)
}

function RequireCommand([string]$Name){
  $cmd=Get-Command $Name -ErrorAction SilentlyContinue
  if(-not $cmd){throw "Missing command: $Name"}
  return $cmd
}

function RunChecked([string]$Label,[scriptblock]$Action){
  Write-Host "`n$Label" -ForegroundColor Cyan
  & $Action
  if($LASTEXITCODE -ne 0){throw "$Label RED ($LASTEXITCODE)"}
}

function BackupFile([string]$Path,[string]$Name){
  if(Test-Path -LiteralPath $Path){
    Copy-Item -LiteralPath $Path -Destination (Join-Path $backup $Name) -Force
  }
}

Write-Host @'
============================================================
 VERTEX - DEFAULT AETHER VIOLET V4
 REAL DESKTOP THEME / FANTASY COCKPIT SKIN
============================================================
'@ -ForegroundColor Magenta

foreach($required in @(
  $startup,$base,$ui,$core,$reports,$cockpit,$panels,$shell,$frame,
  $status,$editor,$packageJson,$coreCargo,$tauriCargo
)){
  if(-not(Test-Path -LiteralPath $required)){
    throw "Required artifact missing: $required"
  }
}

$cargo=RequireCommand 'cargo'
$pnpm=RequireCommand 'pnpm'

Write-Host "`n[0/11] CURRENT COCKPIT BASELINE" -ForegroundColor Yellow

$shellText=[IO.File]::ReadAllText($shell)
$editorText=[IO.File]::ReadAllText($editor)

$baseline=@(
  [pscustomobject]@{
    Name='Cockpit Shell'
    Pass=$shellText.Contains('vertex-cockpit')
  },
  [pscustomobject]@{
    Name='Docking Layout'
    Pass=$shellText.Contains('dock-overlay')
  },
  [pscustomobject]@{
    Name='Editor preserved'
    Pass=$editorText.Contains('<VertexCockpitShell>')
  },
  [pscustomobject]@{
    Name='GUI Preview preserved'
    Pass=$editorText.Contains('<VertexLivePreview />')
  },
  [pscustomobject]@{
    Name='VertexHub preserved'
    Pass=$editorText.Contains('<VertexHubDock />')
  }
)

foreach($item in $baseline){
  if(-not $item.Pass){throw "Baseline missing: $($item.Name)"}
  Write-Host ("  {0,-34} GREEN" -f $item.Name) -ForegroundColor Green
}

RunChecked '[baseline] frontend build' {
  Push-Location $ui
  try{& $pnpm.Source build}finally{Pop-Location}
}

Write-Host "`n[1/11] BACKUP" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item -LiteralPath $cockpit -Destination (Join-Path $backup 'vertex-cockpit') -Recurse -Force
BackupFile $editor 'VertexEditorDock.vue'
Write-Host "Backup: $backup" -ForegroundColor Green

try{
  Write-Host "`n[2/11] CREATE AETHER VIOLET DESIGN TOKENS" -ForegroundColor Yellow

  $theme=@'
/* ============================================================
   VERTEX AETHER VIOLET
   Default VSA desktop visual system.
   Primary: deep navy / indigo / violet
   Secondary: ice cyan
   Semantic: green / amber / red
   ============================================================ */

.vertex-cockpit {
  /* Core surfaces */
  --vertex-bg-deep: #070812;
  --vertex-bg-panel: #0c0f1d;
  --vertex-bg-panel-raised: #12162a;
  --vertex-bg-hover: #171d37;

  /* Structural lines */
  --vertex-line: #242b46;
  --vertex-line-bright: #38446a;
  --vertex-line-violet: #5646a6;

  /* Typography */
  --vertex-text: #d7def0;
  --vertex-muted: #8d97b8;
  --vertex-faint: #5d6688;

  /* New default accent */
  --vertex-blue: #7c5cff;
  --vertex-blue-bright: #a98cff;
  --vertex-blue-soft: #251f52;
  --vertex-violet: #8b5cf6;
  --vertex-violet-bright: #b89cff;
  --vertex-violet-deep: #5b38c7;
  --vertex-cyan: #62d8ff;
  --vertex-cyan-soft: #18364d;

  /* Semantic */
  --vertex-green: #66e2b1;
  --vertex-amber: #f2c66d;
  --vertex-red: #ff748f;

  /* Glows */
  --vertex-glow-primary: rgba(139, 92, 246, .34);
  --vertex-glow-soft: rgba(124, 92, 255, .13);
  --vertex-glow-cyan: rgba(98, 216, 255, .16);

  color: var(--vertex-text);
  background:
    radial-gradient(
      circle at 52% -14%,
      rgba(116, 79, 214, .19),
      transparent 34%
    ),
    radial-gradient(
      circle at 12% 18%,
      rgba(72, 111, 221, .08),
      transparent 30%
    ),
    linear-gradient(
      145deg,
      #070812 0%,
      #090b18 44%,
      #080916 100%
    ) !important;
}

/* ------------------------------------------------------------
   Aether shell atmosphere
   ------------------------------------------------------------ */

.vertex-cockpit::before {
  position: absolute;
  z-index: 0;
  inset: 0;
  pointer-events: none;
  content: "";
  opacity: .42;
  background-image:
    linear-gradient(rgba(120, 101, 208, .022) 1px, transparent 1px),
    linear-gradient(90deg, rgba(120, 101, 208, .022) 1px, transparent 1px);
  background-size: 42px 42px;
  mask-image:
    linear-gradient(
      to bottom,
      rgba(0,0,0,.85),
      rgba(0,0,0,.22) 65%,
      transparent
    );
}

/* ------------------------------------------------------------
   Header / status deck
   ------------------------------------------------------------ */

.vertex-cockpit .cockpit-top-deck {
  background:
    radial-gradient(
      circle at 34% -70%,
      rgba(139,92,246,.20),
      transparent 48%
    ),
    linear-gradient(
      180deg,
      rgba(17,20,39,.98),
      rgba(8,10,20,.98)
    ) !important;
  border-bottom-color: rgba(116, 91, 214, .58) !important;
  box-shadow:
    0 8px 32px rgba(0,0,0,.31),
    0 1px 0 rgba(169,140,255,.12) inset !important;
}

.vertex-cockpit .cockpit-top-deck::after {
  background:
    linear-gradient(
      90deg,
      transparent 2%,
      rgba(98,216,255,.14) 14%,
      rgba(169,140,255,.72) 48%,
      rgba(98,216,255,.16) 78%,
      transparent 98%
    ) !important;
  box-shadow: 0 0 18px rgba(139,92,246,.24);
}

.vertex-cockpit .cockpit-brand,
.vertex-cockpit .cockpit-clock {
  border-color: rgba(80, 75, 130, .62) !important;
  background:
    linear-gradient(
      180deg,
      rgba(16,19,37,.96),
      rgba(8,10,20,.97)
    ) !important;
}

.vertex-cockpit .brand-mark {
  border-color: rgba(169,140,255,.72) !important;
  background:
    radial-gradient(
      circle,
      rgba(139,92,246,.30),
      rgba(29,24,68,.95) 55%,
      #101225
    ) !important;
  box-shadow:
    0 0 18px rgba(139,92,246,.22),
    inset 0 0 16px rgba(98,216,255,.06) !important;
}

.vertex-cockpit .brand-mark span {
  color: var(--vertex-violet-bright) !important;
  text-shadow: 0 0 12px rgba(169,140,255,.54);
}

.vertex-cockpit .cockpit-brand strong {
  color: #e4e4f7 !important;
}

.vertex-cockpit .cockpit-brand small {
  color: #777fa3 !important;
}

/* ------------------------------------------------------------
   Status cards
   ------------------------------------------------------------ */

.vertex-cockpit .status-cell {
  border-color: rgba(55,63,103,.86) !important;
  background:
    radial-gradient(
      circle at 82% -55%,
      rgba(139,92,246,.12),
      transparent 50%
    ),
    linear-gradient(
      155deg,
      rgba(19,23,45,.98),
      rgba(9,11,22,.99)
    ) !important;
  box-shadow:
    inset 0 1px 0 rgba(255,255,255,.022),
    inset 0 0 26px rgba(112,84,218,.028);
}

.vertex-cockpit .status-cell::after {
  background:
    linear-gradient(
      180deg,
      transparent,
      rgba(169,140,255,.95),
      rgba(98,216,255,.62),
      transparent
    ) !important;
  box-shadow: 0 0 12px rgba(139,92,246,.32);
}

/* ------------------------------------------------------------
   Dock columns / workspace
   ------------------------------------------------------------ */

.vertex-cockpit .cockpit-editor-surface {
  background:
    radial-gradient(
      circle at 58% 0%,
      rgba(126,88,226,.055),
      transparent 36%
    ),
    radial-gradient(
      circle at 20% 70%,
      rgba(72,125,214,.025),
      transparent 32%
    ),
    #070812 !important;
}

.vertex-cockpit .dock-column,
.vertex-cockpit .dock-bottom {
  background:
    linear-gradient(
      180deg,
      rgba(11,14,28,.995),
      rgba(7,9,18,.995)
    ) !important;
}

.vertex-cockpit .dock-left {
  border-right-color: rgba(79,69,132,.72) !important;
  box-shadow:
    10px 0 34px rgba(0,0,0,.22),
    2px 0 18px rgba(119,83,220,.035) !important;
}

.vertex-cockpit .dock-right {
  border-left-color: rgba(79,69,132,.72) !important;
  box-shadow:
    -10px 0 34px rgba(0,0,0,.22),
    -2px 0 18px rgba(119,83,220,.035) !important;
}

.vertex-cockpit .dock-bottom {
  border-top-color: rgba(79,69,132,.72) !important;
}

/* ------------------------------------------------------------
   Panel frame
   ------------------------------------------------------------ */

.vertex-cockpit .panel-frame {
  border-color: rgba(50,58,97,.94) !important;
  background:
    radial-gradient(
      circle at 72% -40%,
      rgba(135,92,246,.09),
      transparent 48%
    ),
    linear-gradient(
      180deg,
      rgba(17,21,41,.99),
      rgba(8,10,20,.995)
    ) !important;
  box-shadow:
    inset 0 1px 0 rgba(255,255,255,.022),
    0 14px 38px rgba(0,0,0,.19) !important;
}

.vertex-cockpit .panel-head {
  border-bottom-color: rgba(58,66,108,.88) !important;
  background:
    linear-gradient(
      90deg,
      rgba(119,82,218,.11),
      rgba(61,79,143,.045) 44%,
      transparent 78%
    ),
    rgba(10,13,27,.96) !important;
}

.vertex-cockpit .panel-title strong {
  color: #cbd1e7 !important;
}

.vertex-cockpit .panel-chevron,
.vertex-cockpit .panel-status.tone-blue {
  color: var(--vertex-violet-bright) !important;
}

.vertex-cockpit .panel-action {
  border-color: #343c62 !important;
  background: #0d1020 !important;
  color: #8e98bc !important;
}

.vertex-cockpit .panel-action:hover {
  border-color: #755bcb !important;
  background:
    linear-gradient(
      180deg,
      rgba(42,34,87,.98),
      rgba(22,19,47,.98)
    ) !important;
  color: #c7b7ff !important;
  box-shadow: 0 0 14px rgba(139,92,246,.12);
}

/* ------------------------------------------------------------
   Magnetic dock targets
   ------------------------------------------------------------ */

.vertex-cockpit .dock-target {
  border-color: rgba(169,140,255,.46) !important;
  background:
    radial-gradient(
      circle at center,
      rgba(102,83,196,.27),
      rgba(25,23,58,.78) 60%,
      rgba(12,14,30,.84)
    ) !important;
  box-shadow:
    inset 0 0 42px rgba(139,92,246,.10),
    0 12px 36px rgba(0,0,0,.26) !important;
}

.vertex-cockpit .dock-target.active {
  border-color: #c7b7ff !important;
  background:
    radial-gradient(
      circle at center,
      rgba(132,94,238,.39),
      rgba(31,28,72,.92) 62%
    ) !important;
  box-shadow:
    inset 0 0 52px rgba(139,92,246,.15),
    0 0 34px rgba(139,92,246,.26) !important;
}

.vertex-cockpit .dock-target strong {
  color: #ddd5ff !important;
}

.vertex-cockpit .dock-target span {
  color: #8dbbd6 !important;
}

/* ------------------------------------------------------------
   Floating panels
   ------------------------------------------------------------ */

.vertex-cockpit .floating-panel {
  border: 1px solid rgba(112,88,196,.52);
  box-shadow:
    0 24px 76px rgba(0,0,0,.58),
    0 0 0 1px rgba(169,140,255,.05),
    0 0 30px rgba(139,92,246,.07) !important;
}

/* ------------------------------------------------------------
   Command rail
   ------------------------------------------------------------ */

.vertex-cockpit .cockpit-command-rail {
  border-color: rgba(65,71,119,.92) !important;
  background:
    linear-gradient(
      180deg,
      rgba(15,18,35,.97),
      rgba(8,10,21,.97)
    ) !important;
  box-shadow:
    0 10px 30px rgba(0,0,0,.34),
    0 0 22px rgba(139,92,246,.035) !important;
}

.vertex-cockpit .cockpit-command-rail button {
  border-color: #30385a !important;
  background: #0c0f1d !important;
  color: #7e89ae !important;
}

.vertex-cockpit .cockpit-command-rail button:hover,
.vertex-cockpit .cockpit-command-rail button.active {
  border-color: #7358c9 !important;
  background: #211b46 !important;
  color: #c4b3ff !important;
  box-shadow: inset 0 0 16px rgba(139,92,246,.08);
}

/* ------------------------------------------------------------
   Current bottom status surface.
   This remains temporary infrastructure; future Player HUD replaces it.
   ------------------------------------------------------------ */

.vertex-cockpit .status-bar {
  border-top-color: rgba(74,68,126,.82) !important;
  background:
    linear-gradient(
      90deg,
      rgba(28,22,62,.96),
      rgba(9,11,23,.98) 28%,
      rgba(9,11,23,.98) 72%,
      rgba(27,23,58,.96)
    ) !important;
  box-shadow:
    0 -1px 0 rgba(169,140,255,.06),
    0 -8px 24px rgba(0,0,0,.13);
}

/* ------------------------------------------------------------
   Scrollbars
   ------------------------------------------------------------ */

.vertex-cockpit *::-webkit-scrollbar-thumb {
  background:
    linear-gradient(
      180deg,
      #4a426f,
      #2d3552
    ) !important;
}

.vertex-cockpit *::-webkit-scrollbar-thumb:hover {
  background:
    linear-gradient(
      180deg,
      #65519f,
      #394365
    ) !important;
}

/* ------------------------------------------------------------
   Selection / focus accents
   ------------------------------------------------------------ */

.vertex-cockpit button:focus-visible,
.vertex-cockpit input:focus-visible,
.vertex-cockpit textarea:focus-visible,
.vertex-cockpit [tabindex]:focus-visible {
  outline: 1px solid rgba(169,140,255,.78);
  outline-offset: 1px;
  box-shadow: 0 0 0 3px rgba(139,92,246,.11);
}

/* ------------------------------------------------------------
   Wide 27-inch atmospheric spacing
   ------------------------------------------------------------ */

@media (min-width: 2200px) {
  .vertex-cockpit {
    --cockpit-base-font: 14px;
    --cockpit-caption: 11px;
    --cockpit-panel-title: 14px;
    --cockpit-value: 16px;
    --cockpit-panel-header: 44px;
  }

  .vertex-cockpit .cockpit-top-deck {
    padding: 9px 10px !important;
    gap: 8px !important;
  }

  .vertex-cockpit .dock-column {
    gap: 10px !important;
    padding: 10px !important;
  }
}
'@
  New-Item -ItemType Directory -Path $themeDir -Force|Out-Null
  WriteUtf8 $themeCss $theme

  Write-Host 'Aether Violet tokens          : CREATED' -ForegroundColor Green
  Write-Host 'Primary accent                : VIOLET / INDIGO' -ForegroundColor Green
  Write-Host 'Secondary accent              : ICE CYAN' -ForegroundColor Green
  Write-Host 'Semantic colors               : PRESERVED' -ForegroundColor Green

  Write-Host "`n[3/11] DOCK THEME INTO REAL COCKPIT SHELL" -ForegroundColor Yellow

  $shellText=[IO.File]::ReadAllText($shell)
  $importLine="import './theme/vertex-aether-violet.css'"

  if(-not $shellText.Contains($importLine)){
    $scriptMatch=[regex]::Match(
      $shellText,
      '<script setup lang="ts">\s*',
      [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if(-not $scriptMatch.Success){
      throw 'VertexCockpitShell script setup anchor not found.'
    }

    $insertAt=$scriptMatch.Index+$scriptMatch.Length
    $shellText=
      $shellText.Substring(0,$insertAt)+
      $importLine+"`r`n"+
      $shellText.Substring($insertAt)

    WriteUtf8 $shell $shellText
  }

  Write-Host 'Real Cockpit Shell theme       : DOCKED' -ForegroundColor Green

  Write-Host "`n[4/11] DEFAULT PALETTE IDENTITY PATCH" -ForegroundColor Yellow

  $shellText=[IO.File]::ReadAllText($shell)

  $replacements=[ordered]@{
    '--vertex-bg-deep: #070b10;'='--vertex-bg-deep: #070812;'
    '--vertex-bg-panel: #0c121a;'='--vertex-bg-panel: #0c0f1d;'
    '--vertex-bg-panel-raised: #111923;'='--vertex-bg-panel-raised: #12162a;'
    '--vertex-bg-hover: #14202c;'='--vertex-bg-hover: #171d37;'
    '--vertex-line: #1c2935;'='--vertex-line: #242b46;'
    '--vertex-line-bright: #26394b;'='--vertex-line-bright: #38446a;'
    '--vertex-text: #cbd5df;'='--vertex-text: #d7def0;'
    '--vertex-muted: #718195;'='--vertex-muted: #8d97b8;'
    '--vertex-faint: #455364;'='--vertex-faint: #5d6688;'
    '--vertex-blue: #168cff;'='--vertex-blue: #7c5cff;'
    '--vertex-blue-bright: #3ab8ff;'='--vertex-blue-bright: #a98cff;'
    '--vertex-blue-soft: #102c44;'='--vertex-blue-soft: #251f52;'
  }

  foreach($pair in $replacements.GetEnumerator()){
    if($shellText.Contains($pair.Key)){
      $shellText=$shellText.Replace($pair.Key,$pair.Value)
    }
  }

  WriteUtf8 $shell $shellText

  Write-Host 'Legacy blue defaults           : REBASED' -ForegroundColor Green
  Write-Host 'Aether palette                 : DEFAULT' -ForegroundColor Green

  Write-Host "`n[5/11] FRONTEND TYPECHECK" -ForegroundColor Yellow

  Push-Location $ui
  try{
    RunChecked '[aether] vue-tsc' {
      & $pnpm.Source exec vue-tsc --noEmit
    }
  }finally{
    Pop-Location
  }

  Write-Host "`n[6/11] FRONTEND BUILD" -ForegroundColor Yellow

  Push-Location $ui
  try{
    RunChecked '[aether] vite build' {
      & $pnpm.Source exec vite build
    }
  }finally{
    Pop-Location
  }

  Write-Host "`n[7/11] VISUAL / SAFETY AUDIT" -ForegroundColor Yellow

  $themeNow=[IO.File]::ReadAllText($themeCss)
  $shellNow=[IO.File]::ReadAllText($shell)
  $editorNow=[IO.File]::ReadAllText($editor)

  $audits=@(
    [pscustomobject]@{
      Name='Aether theme import'
      Pass=$shellNow.Contains("import './theme/vertex-aether-violet.css'")
    },
    [pscustomobject]@{
      Name='Default Violet'
      Pass=$themeNow.Contains('--vertex-violet: #8b5cf6')
    },
    [pscustomobject]@{
      Name='Default Indigo'
      Pass=$themeNow.Contains('--vertex-blue: #7c5cff')
    },
    [pscustomobject]@{
      Name='Ice Cyan'
      Pass=$themeNow.Contains('--vertex-cyan: #62d8ff')
    },
    [pscustomobject]@{
      Name='27-inch readability'
      Pass=$themeNow.Contains('@media (min-width: 2200px)')
    },
    [pscustomobject]@{
      Name='Dock glow'
      Pass=$themeNow.Contains('.dock-target.active')
    },
    [pscustomobject]@{
      Name='Panel skin'
      Pass=$themeNow.Contains('.panel-frame')
    },
    [pscustomobject]@{
      Name='No eval'
      Pass=(-not $themeNow.Contains('eval('))
    },
    [pscustomobject]@{
      Name='No remote import'
      Pass=(-not $themeNow.Contains('http://') -and -not $themeNow.Contains('https://'))
    },
    [pscustomobject]@{
      Name='Editor preserved'
      Pass=$editorNow.Contains('<VertexCockpitShell>')
    },
    [pscustomobject]@{
      Name='GUI Preview preserved'
      Pass=$editorNow.Contains('<VertexLivePreview />')
    },
    [pscustomobject]@{
      Name='VertexHub preserved'
      Pass=$editorNow.Contains('<VertexHubDock />')
    }
  )

  foreach($audit in $audits){
    if(-not $audit.Pass){throw "Aether audit RED: $($audit.Name)"}
    Write-Host ("  {0,-38} GREEN" -f $audit.Name) -ForegroundColor Green
  }

  Write-Host "`n[8/11] TAURI CLEAN-ROOM CHECK" -ForegroundColor Yellow

  $previousCargoTarget=$env:CARGO_TARGET_DIR
  try{
    if(Test-Path -LiteralPath $tauriCheckTarget){
      Remove-Item -LiteralPath $tauriCheckTarget -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tauriCheckTarget -Force|Out-Null
    $env:CARGO_TARGET_DIR=$tauriCheckTarget

    RunChecked '[release] Tauri cargo check - clean room' {
      & $cargo.Source check --manifest-path $tauriCargo --all-targets
    }
  }finally{
    $env:CARGO_TARGET_DIR=$previousCargoTarget
  }

  Write-Host "`n[9/11] WORKSPACE RELEASE GATE" -ForegroundColor Yellow

  RunChecked '[release] cargo check --workspace --all-targets' {
    & $cargo.Source check --manifest-path $coreCargo --workspace --all-targets
  }

  RunChecked '[release] cargo test --workspace' {
    & $cargo.Source test --manifest-path $coreCargo --workspace
  }

  Write-Host "`n[10/11] FINAL FRONTEND GATE" -ForegroundColor Yellow

  Push-Location $ui
  try{
    RunChecked '[release] pnpm build' {
      & $pnpm.Source build
    }
  }finally{
    Pop-Location
  }

  Write-Host "`n[11/11] REPORT" -ForegroundColor Yellow

  [ordered]@{
    schema='vertex.cic.default-aether-violet.v4'
    timestamp=(Get-Date).ToString('o')
    status='GREEN'
    mission='VSA DEFAULT AETHER VIOLET V4'
    default_theme=[ordered]@{
      name='AETHER VIOLET'
      primary='#7c5cff'
      primary_bright='#a98cff'
      violet='#8b5cf6'
      cyan='#62d8ff'
      bg_deep='#070812'
      bg_panel='#0c0f1d'
      text='#d7def0'
      semantic_green='#66e2b1'
      semantic_amber='#f2c66d'
      semantic_red='#ff748f'
    }
    design=[ordered]@{
      mood='SLIGHTLY VIOLET / FANTASY / PREMIUM SCI-FI'
      readability='27-INCH FIRST'
      dock_system='PRESERVED'
      magnetic_dock='RETHEMED'
      panel_frames='RETHEMED'
      header='RETHEMED'
      bottom_surface='TEMP STATUS / FUTURE PLAYER HUD'
    }
    preserved=[ordered]@{
      editor='YES'
      gui_live_preview='YES'
      vertexhub='YES'
      mothership='UNTOUCHED'
      runtime_bus='UNTOUCHED'
      telemetry='REAL SIGNAL ONLY'
    }
    validation=[ordered]@{
      vue_typecheck='GREEN'
      frontend_build='GREEN'
      tauri_check='GREEN'
      workspace_check='GREEN'
      workspace_test='GREEN'
    }
    next_target='ROLE LAYOUT: HYPERAGENT CHAT / VVE EXPLORER / UTILITY PANELS / PLAYER HUD'
    backup=$backup
  }|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $report -Encoding UTF8

  Write-Host @"
============================================================
 VERTEX - DEFAULT AETHER VIOLET V4 GREEN
============================================================
 Real Desktop CSS                         UPDATED
 Default Theme                            AETHER VIOLET
 Deep Navy Black                          LOCKED
 Indigo Primary #7c5cff                   LOCKED
 Violet #8b5cf6                           LOCKED
 Bright Violet #a98cff                    LOCKED
 Ice Cyan #62d8ff                         LOCKED
 Fantasy Atmosphere                       ONLINE
 27-inch Readability                      PRESERVED
 Cockpit Header                           RETHEMED
 Status Deck                              RETHEMED
 Dock Columns                             RETHEMED
 Panel Frames                             RETHEMED
 Magnetic Dock Targets                    RETHEMED
 Floating Panels                          RETHEMED
 Command Rail                             RETHEMED
 Current Bottom Surface                   TEMP / HUD-READY
 Docking Architecture                     PRESERVED
 Existing Editor                          PRESERVED
 GUI Live Preview                         PRESERVED
 VertexHub                                PRESERVED
 Real Telemetry                           PRESERVED
 Mothership / Runtime Bus                 UNTOUCHED
 Frontend Typecheck                       GREEN
 Frontend Build                           GREEN
 Tauri Check                              GREEN
 Workspace Release Gate                   GREEN
------------------------------------------------------------
 NEXT TARGET:
 HYPERAGENT CHAT / VVE TREE / UTILITY PANELS / PLAYER HUD
============================================================
 VERTEX DEFAULT COLOR SYSTEM: EVOLVED
 WE ARE VERTEX.
============================================================
"@ -ForegroundColor Green
}
catch{
  Write-Host "`n============================================================" -ForegroundColor Red
  Write-Host ' DEFAULT AETHER VIOLET V4 RED - DAMAGE CONTROL' -ForegroundColor Red
  Write-Host '============================================================' -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red

  New-Item -ItemType Directory -Path $failed -Force|Out-Null

  if(Test-Path -LiteralPath $cockpit){
    Copy-Item -LiteralPath $cockpit -Destination (Join-Path $failed 'vertex-cockpit.failed') -Recurse -Force -ErrorAction SilentlyContinue
  }

  $cockpitBackup=Join-Path $backup 'vertex-cockpit'
  $editorBackup=Join-Path $backup 'VertexEditorDock.vue'

  if(Test-Path -LiteralPath $cockpitBackup){
    if(Test-Path -LiteralPath $cockpit){
      Remove-Item -LiteralPath $cockpit -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -LiteralPath $cockpitBackup -Destination $cockpit -Recurse -Force
  }

  if(Test-Path -LiteralPath $editorBackup){
    Copy-Item -LiteralPath $editorBackup -Destination $editor -Force
  }

  Write-Host 'Cockpit rollback                  : COMPLETE' -ForegroundColor Yellow
  Write-Host 'Editor rollback                   : COMPLETE' -ForegroundColor Yellow
  Write-Host 'Mothership / Runtime Bus          : UNTOUCHED' -ForegroundColor Yellow
  Write-Host "Failure evidence: $failed" -ForegroundColor Yellow
  throw
}
}