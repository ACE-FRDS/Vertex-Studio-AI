#requires -Version 7.0
$ErrorActionPreference = "Stop"

# Vertex Project Mark - Global Brand Patch
# Applies the single Vertex Project Mark to Vertex AI Knowledge Hub + Vera.
# Preserves canonical knowledge, Google verification and AI endpoints.

$projectRoot = "G:\Vertex_Project\Development\vertex_studio_ai"
$hubRoot  = Join-Path $projectRoot "VertexHub"
$siteRoot = Join-Path $hubRoot "site"
$brandDir = Join-Path $siteRoot "assets\brand"

if (-not (Test-Path $siteRoot)) { throw "Site root missing: $siteRoot" }

New-Item -ItemType Directory -Force $brandDir | Out-Null

$svg = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 205 210" role="img" aria-labelledby="title desc">
  <title id="title">VERTEX Project</title>
  <desc id="desc">シアンとブルーを組み合わせたV字型のブランドマーク</desc>
  <path fill="#3AABE0" d="M17 18.5h65L103.5 52 63.8 119.4Z"/>
  <path fill="#465BC5" d="M119.2 18.5H196L90.3 189.8l-35.1-58.9Z"/>
</svg>

'@
$markPath = Join-Path $brandDir "vertex-project-mark.svg"
$svg | Set-Content $markPath -Encoding UTF8

# favicon uses the exact same master mark.
Copy-Item $markPath (Join-Path $siteRoot "favicon.svg") -Force

$indexPath = Join-Path $siteRoot "index.html"
if (-not (Test-Path $indexPath)) { throw "index.html missing: $indexPath" }

$html = Get-Content $indexPath -Raw

# Add favicon if missing.
if ($html -notmatch 'rel="icon"') {
    $html = $html -replace '</head>', '<link rel="icon" href="/favicon.svg" type="image/svg+xml">`r`n</head>'
}

# Replace Phase 4 brand dot with actual Vertex Project Mark.
$html = $html -replace '<span class="core-dot"></span>VERTEX AI KNOWLEDGE HUB',
    '<img class="vertex-mark brand-mark" src="/assets/brand/vertex-project-mark.svg" alt="Vertex Project Mark">VERTEX AI KNOWLEDGE HUB'

# Replace Vera V placeholder with the common Vertex mark.
$html = $html -replace '<div class="vera-mark">V</div>',
    '<div class="vera-mark"><img class="vertex-mark vera-logo" src="/assets/brand/vertex-project-mark.svg" alt="Vertex Project Mark"></div>'

Set-Content $indexPath $html -Encoding UTF8

$cssPath = Join-Path $siteRoot "assets\css\components.css"
if (Test-Path $cssPath) {
    $css = Get-Content $cssPath -Raw
    if ($css -notmatch '\.brand-mark\{') {
        $css += @'

.vertex-mark{display:block;object-fit:contain}
.brand-mark{width:27px;height:29px;filter:drop-shadow(0 0 10px rgba(114,230,255,.22))}
.vera-logo{width:38px;height:40px;filter:drop-shadow(0 0 14px rgba(114,230,255,.24))}
'@
        Set-Content $cssPath $css -Encoding UTF8
    }
}

# Validate public brand assets and protected endpoints.
$routes = @(
    "/",
    "/favicon.svg",
    "/assets/brand/vertex-project-mark.svg",
    "/bootstrap/",
    "/llms.txt",
    "/.well-known/vertex-ai.json",
    "/ai/vertex-public-knowledge.json"
)

Write-Host ""
Write-Host "Validating Vertex Project Mark rollout..." -ForegroundColor Cyan

$results = foreach ($route in $routes) {
    try {
        $r = Invoke-WebRequest "https://vertex.a-portal.net$route" -UseBasicParsing -TimeoutSec 20
        [pscustomobject]@{Route=$route;Status=$r.StatusCode;Result="OK"}
    } catch {
        [pscustomobject]@{Route=$route;Status="ERROR";Result=$_.Exception.Message}
    }
}
$results | Format-Table -AutoSize

if (@($results | Where-Object Result -ne "OK").Count -gt 0) {
    throw "Brand rollout validation failed."
}

Write-Host ""
Write-Host "VERTEX PROJECT MARK ONLINE" -ForegroundColor Green
Write-Host "Hub favicon : /favicon.svg"
Write-Host "Hub header  : Vertex Project Mark"
Write-Host "Vera mark   : Vertex Project Mark"
Write-Host "Canonical   : PRESERVED"
Write-Host "AI endpoints: PRESERVED"
