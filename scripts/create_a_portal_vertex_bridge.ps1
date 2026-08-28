#requires -Version 7.0
$ErrorActionPreference = "Stop"

# Vertex AI Knowledge Hub - Main Site Bridge Snippet Generator
# Does NOT modify a-portal.net automatically.
# Generates a safe, ordinary HTML bridge file that can be inserted/published
# from the existing a-portal.net main site.

$projectRoot = "G:\Vertex_Project\Development\vertex_studio_ai"
$outDir = Join-Path $projectRoot "VertexHub\bridge"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$bridge = @'
<section id="vertex-ai-knowledge-hub">
  <h2>Vertex AI Knowledge Hub</h2>
  <p>
    Official public canonical knowledge endpoint for the Vertex project.
    Research, terminology, architecture, source records, and machine-readable
    knowledge are published here for AI and human reference.
  </p>
  <p>
    <a href="https://vertex.a-portal.net/bootstrap/"
       rel="external">
      Open Vertex AI Knowledge Hub
    </a>
  </p>
</section>
'@

$bridgePath = Join-Path $outDir "a-portal_vertex_ai_knowledge_hub_bridge.html"
$bridge | Set-Content $bridgePath -Encoding UTF8

Write-Host ""
Write-Host "MAIN-SITE BRIDGE READY" -ForegroundColor Green
Write-Host "Snippet : $bridgePath"
Write-Host ""
Write-Host "Target  : https://vertex.a-portal.net/bootstrap/"
Write-Host ""
Write-Host "NOTE: This script intentionally does not guess or overwrite the a-portal.net document root." -ForegroundColor Yellow
