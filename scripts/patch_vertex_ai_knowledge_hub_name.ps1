#requires -Version 7.0
$ErrorActionPreference = "Stop"

# Vertex AI Knowledge Hub - Rename Patch
# Renames public-facing "Vertex Hub" identity without changing URL or IIS bindings.

$projectRoot = "G:\Vertex_Project\Development\vertex_studio_ai"
$hubRoot  = Join-Path $projectRoot "VertexHub"
$siteRoot = Join-Path $hubRoot "site"
$dataRoot = Join-Path $hubRoot "data"

if (-not (Test-Path $siteRoot)) { throw "Site root missing: $siteRoot" }

$oldName = "Vertex Hub"
$newName = "Vertex AI Knowledge Hub"

# Generated/public text files.
$targets = @()
$targets += Get-ChildItem $siteRoot -Recurse -File -Include *.html,*.json,*.txt,*.xml -ErrorAction SilentlyContinue
$deployment = Join-Path $hubRoot "deployment.json"
if (Test-Path $deployment) { $targets += Get-Item $deployment }

foreach ($file in $targets) {
    $text = Get-Content $file.FullName -Raw
    if ($text.Contains($oldName)) {
        $text = $text.Replace($oldName, $newName)
        Set-Content $file.FullName $text -Encoding UTF8
        Write-Host "Updated: $($file.FullName)" -ForegroundColor DarkGray
    }
}

# Canonical concept: keep stable id for compatibility, rename display identity.
$conceptPath = Join-Path $dataRoot "concepts.json"
if (Test-Path $conceptPath) {
    $concepts = @(Get-Content $conceptPath -Raw | ConvertFrom-Json)
    foreach ($c in $concepts) {
        if ($c.id -eq "vertex-hub") {
            $c.name = $newName
            $c.definition = "Vertexプロジェクトの公式公開Canonical Knowledge Endpoint。Research、Lexicon、Architecture、Source Registry、およびAI-readable endpointsを提供する。"
        }
    }
    $concepts | ConvertTo-Json -Depth 12 | Set-Content $conceptPath -Encoding UTF8
}

# Bootstrap must explicitly use the new public name.
$bootstrapJson = Join-Path $siteRoot ".well-known\vertex-ai.json"
if (Test-Path $bootstrapJson) {
    $b = Get-Content $bootstrapJson -Raw | ConvertFrom-Json
    $b.service = $newName
    $b | ConvertTo-Json -Depth 12 | Set-Content $bootstrapJson -Encoding UTF8
}

$checks = @(
    "/",
    "/bootstrap/",
    "/llms.txt",
    "/.well-known/vertex-ai.json",
    "/ai/vertex-public-knowledge.json"
)

Write-Host ""
Write-Host "Validating Vertex AI Knowledge Hub..." -ForegroundColor Cyan
$results = foreach ($route in $checks) {
    try {
        $r = Invoke-WebRequest "https://vertex.a-portal.net$route" -UseBasicParsing -TimeoutSec 20
        [pscustomobject]@{ Route=$route; Status=$r.StatusCode; Result="OK" }
    } catch {
        [pscustomobject]@{ Route=$route; Status="ERROR"; Result=$_.Exception.Message }
    }
}
$results | Format-Table -AutoSize

if (@($results | Where-Object Result -ne "OK").Count -gt 0) {
    throw "Rename validation failed."
}

Write-Host ""
Write-Host "VERTEX AI KNOWLEDGE HUB ONLINE" -ForegroundColor Green
Write-Host "Public URL : https://vertex.a-portal.net/"
Write-Host "Bootstrap  : https://vertex.a-portal.net/bootstrap/"
Write-Host "Vera Entry : https://vertex.a-portal.net/.well-known/vertex-ai.json"
