param(
    [Parameter(Mandatory=$true)]
    [string]$RelativePath
)

$ErrorActionPreference = 'Stop'

$project = 'G:\Vertex_Project\Vertex_Studio_AI'
$active  = Join-Path $project 'HANGER\Startup_Package\VSA_Startup_Package_v0.2'
$public  = Join-Path $project 'Gateway\public'
$peekDir = Join-Path $public 'inspector\peek'

New-Item -ItemType Directory -Force -Path $peekDir | Out-Null

# ------------------------------------------------------------
# Root containment
# ------------------------------------------------------------

$rootFull = [System.IO.Path]::GetFullPath($active).TrimEnd('\') + '\'

$targetFull = [System.IO.Path]::GetFullPath(
    (Join-Path $active $RelativePath)
)

if (-not $targetFull.StartsWith(
    $rootFull,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw 'Path escapes VSA_ACTIVE_WORKSPACE.'
}

if (-not (Test-Path -LiteralPath $targetFull -PathType Leaf)) {
    throw "File not found: $RelativePath"
}

$relative = [System.IO.Path]::GetRelativePath(
    $active,
    $targetFull
) -replace '\\','/'

# ------------------------------------------------------------
# Denied areas
# ------------------------------------------------------------

$segments = $relative -split '/'

$denySegments = @(
    '.git',
    '.idea',
    '.vscode',
    'node_modules',
    'target',
    'dist',
    'build',
    'coverage',
    '.cache',
    '_vertex_reports'
)

foreach ($segment in $segments) {
    if ($denySegments -contains $segment) {
        throw "Denied directory: $segment"
    }
}

# ------------------------------------------------------------
# Extension allowlist
# ------------------------------------------------------------

$allowedExtensions = @(
    '.rs',
    '.toml',
    '.vue',
    '.ts',
    '.tsx',
    '.js',
    '.json',
    '.md',
    '.css',
    '.yaml',
    '.yml',
    '.vxn',
    '.txt'
)

$extension = [System.IO.Path]::GetExtension($targetFull).ToLowerInvariant()

if ($allowedExtensions -notcontains $extension) {
    throw "Extension is not allowed: $extension"
}

# ------------------------------------------------------------
# Secret-like filename rejection
# ------------------------------------------------------------

$name = [System.IO.Path]::GetFileName($targetFull)

$denyNamePatterns = @(
    '.env',
    '.env.*',
    '*token*',
    '*secret*',
    '*credential*',
    '*password*',
    '*.pem',
    '*.key',
    '*.pfx',
    '*.p12'
)

foreach ($pattern in $denyNamePatterns) {
    if ($name -like $pattern) {
        throw "Sensitive filename rejected: $name"
    }
}

# ------------------------------------------------------------
# Size cap
# ------------------------------------------------------------

$file = Get-Item -LiteralPath $targetFull

$maxBytes = 262144   # 256 KiB

if ($file.Length -gt $maxBytes) {
    throw "File too large for Safe Peek: $($file.Length) bytes"
}

# ------------------------------------------------------------
# Read source
# ------------------------------------------------------------

$content = Get-Content `
    -LiteralPath $targetFull `
    -Raw

# Basic embedded-secret guard.
$suspiciousPatterns = @(
    '-----BEGIN PRIVATE KEY-----',
    '-----BEGIN RSA PRIVATE KEY-----',
    'sk-[A-Za-z0-9_-]{20,}',
    'ghp_[A-Za-z0-9]{20,}'
)

foreach ($pattern in $suspiciousPatterns) {
    if ($content -match $pattern) {
        throw 'Potential embedded secret detected. Publication aborted.'
    }
}

# ------------------------------------------------------------
# Ephemeral publication
# ------------------------------------------------------------

$id = [Guid]::NewGuid().ToString('N').Substring(0,20)

$outFile = Join-Path $peekDir "$id.json"
$tmpFile = "$outFile.tmp"

$sha256 = (
    Get-FileHash `
        -LiteralPath $targetFull `
        -Algorithm SHA256
).Hash.ToLowerInvariant()

$data = [ordered]@{
    schema      = 'vsa.inspector.peek.v0.2'
    generatedAt = (Get-Date).ToString('o')

    workspace = 'VSA_Startup_Package_v0.2'

    source = [ordered]@{
        path   = $relative
        size   = $file.Length
        sha256 = $sha256
    }

    security = [ordered]@{
        mode              = 'EXPLICIT_SINGLE_FILE'
        arbitraryRead     = $false
        pathTraversal     = $false
        extensionAllowlist = $true
        maxBytes          = $maxBytes
    }

    content = $content
}

$data |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $tmpFile -Encoding UTF8

Move-Item `
    -LiteralPath $tmpFile `
    -Destination $outFile `
    -Force

$url = "https://vertex.a-portal.net/inspector/peek/$id.json"

Write-Host ''
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' VSA INSPECTOR SAFE PEEK v0.2' -ForegroundColor Green
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host "Path   : $relative"
Write-Host "Bytes  : $($file.Length)"
Write-Host "SHA256 : $sha256"
Write-Host ''
Write-Host "URL:" -ForegroundColor Yellow
Write-Host $url -ForegroundColor Yellow
Write-Host ''
Write-Host "Peek ID: $id"
Write-Host ''
Write-Host 'Delete this Peek after inspection.' -ForegroundColor Yellow
