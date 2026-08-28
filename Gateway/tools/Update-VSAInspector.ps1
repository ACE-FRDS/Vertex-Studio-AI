$ErrorActionPreference = 'Stop'

$project   = 'G:\Vertex_Project\Vertex_Studio_AI'
$public    = Join-Path $project 'Gateway\public'
$inspector = Join-Path $public 'inspector'

New-Item -ItemType Directory -Force -Path $inspector | Out-Null

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)]$Value,
        [int]$Depth = 12
    )

    $tmp = "$Path.tmp"

    $Value |
        ConvertTo-Json -Depth $Depth |
        Set-Content -LiteralPath $tmp -Encoding UTF8

    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# ------------------------------------------------------------
# Basic state
# ------------------------------------------------------------

$now = (Get-Date).ToString('o')

$cloudflared = Get-Service Cloudflared -ErrorAction SilentlyContinue

$appcmd = "$env:windir\System32\inetsrv\appcmd.exe"

$iisState = 'Unknown'
if (Test-Path $appcmd) {
    try {
        $siteLine = & $appcmd list site "vertex" 2>$null
        if ($siteLine -match 'Started') {
            $iisState = 'Started'
        }
        elseif ($siteLine) {
            $iisState = 'Present'
        }
    }
    catch {
        $iisState = 'Error'
    }
}

# ------------------------------------------------------------
# Git
# ------------------------------------------------------------

$gitBranch = (& git -C $project branch --show-current 2>$null)
$gitCommit = (& git -C $project rev-parse --short HEAD 2>$null)

$gitStatusRaw = @(
    & git -C $project status --porcelain=v1 2>$null
)

$changes = @()

foreach ($line in $gitStatusRaw) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    $status = if ($line.Length -ge 2) {
        $line.Substring(0,2)
    } else {
        $line
    }

    $path = if ($line.Length -gt 3) {
        $line.Substring(3)
    } else {
        ''
    }

    $changes += [ordered]@{
        status = $status
        path   = $path
    }
}

$diffStat = @(
    & git -C $project diff --stat 2>$null
)

$cachedDiffStat = @(
    & git -C $project diff --cached --stat 2>$null
)

# ------------------------------------------------------------
# Safe project tree
#
# IMPORTANT:
# - filenames/metadata only
# - no file contents
# - known secret/build/cache areas omitted
# ------------------------------------------------------------

$denyDirs = @(
    '.git',
    '.idea',
    '.vscode',
    'node_modules',
    'target',
    'dist',
    'build',
    'coverage',
    '.cache',
    '.next',
    '.venv',
    'venv',
    '__pycache__'
)

$denyFilePatterns = @(
    '.env',
    '.env.*',
    '*.pem',
    '*.key',
    '*.pfx',
    '*.p12',
    '*token*',
    '*secret*',
    '*credential*',
    '*.bak',
    '*.backup'
)

$maxDepth = 5
$maxItems = 2500

$entries = New-Object System.Collections.Generic.List[object]

function Test-DeniedFile {
    param([string]$Name)

    foreach ($pattern in $denyFilePatterns) {
        if ($Name -like $pattern) {
            return $true
        }
    }

    return $false
}

function Add-Tree {
    param(
        [string]$Directory,
        [int]$Depth
    )

    if ($Depth -gt $maxDepth) {
        return
    }

    if ($entries.Count -ge $maxItems) {
        return
    }

    try {
        $items = Get-ChildItem `
            -LiteralPath $Directory `
            -Force `
            -ErrorAction Stop |
            Sort-Object `
                @{Expression='PSIsContainer';Descending=$true},
                Name
    }
    catch {
        return
    }

    foreach ($item in $items) {

        if ($entries.Count -ge $maxItems) {
            return
        }

        # Never expose Inspector-generated files back into tree scan.
        if (
            $item.FullName.StartsWith(
                $inspector,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            continue
        }

        if ($item.Name -like '_vsa_probe_*') {
            continue
        }

        if ($item.PSIsContainer) {
            if ($denyDirs -contains $item.Name) {
                continue
            }
        }
        else {
            if (Test-DeniedFile $item.Name) {
                continue
            }
        }

        $relative = [System.IO.Path]::GetRelativePath(
            $project,
            $item.FullName
        ) -replace '\\','/'

        $entry = [ordered]@{
            path         = $relative
            type         = if ($item.PSIsContainer) { 'directory' } else { 'file' }
            size         = if ($item.PSIsContainer) { $null } else { $item.Length }
            lastModified = $item.LastWriteTime.ToString('o')
        }

        $entries.Add($entry)

        if ($item.PSIsContainer -and $Depth -lt $maxDepth) {
            Add-Tree `
                -Directory $item.FullName `
                -Depth ($Depth + 1)
        }
    }
}

Add-Tree -Directory $project -Depth 0

$workspaceMarkers = @(
    $entries |
        Where-Object {
            $_.type -eq 'file' -and (
                $_.path -match '(^|/)Cargo\.toml$' -or
                $_.path -match '(^|/)package\.json$' -or
                $_.path -match '(^|/)pyproject\.toml$'
            )
        } |
        Select-Object -First 100
)

# ------------------------------------------------------------
# health.json
# ------------------------------------------------------------

$health = [ordered]@{
    probe         = 'VSA-GATEWAY'
    version       = '0.1'
    generatedAt   = $now
    projectExists = Test-Path $project
    cloudflared   = if ($cloudflared) {
        $cloudflared.Status.ToString()
    } else {
        'NotFound'
    }
    iisSite       = $iisState
    inspector     = 'Ready'
}

Write-JsonAtomic `
    -Path (Join-Path $public 'health.json') `
    -Value $health

# ------------------------------------------------------------
# project.json
# ------------------------------------------------------------

$projectStatus = [ordered]@{
    schema       = 'vsa.inspector.project.v0.1'
    generatedAt  = $now

    project = [ordered]@{
        name   = 'Vertex Studio AI'
        root   = 'G:\Vertex_Project\Vertex_Studio_AI'
        exists = Test-Path $project
    }

    git = [ordered]@{
        branch     = "$gitBranch"
        commit     = "$gitCommit"
        dirtyCount = $changes.Count
    }

    tree = [ordered]@{
        maxDepth   = $maxDepth
        entryCount = $entries.Count
        truncated  = ($entries.Count -ge $maxItems)
    }

    workspaceMarkers = $workspaceMarkers
}

Write-JsonAtomic `
    -Path (Join-Path $inspector 'project.json') `
    -Value $projectStatus

# ------------------------------------------------------------
# tree.json
# ------------------------------------------------------------

$treeStatus = [ordered]@{
    schema      = 'vsa.inspector.tree.v0.1'
    generatedAt = $now
    maxDepth    = $maxDepth
    maxItems    = $maxItems
    count       = $entries.Count
    truncated   = ($entries.Count -ge $maxItems)
    entries     = $entries
}

Write-JsonAtomic `
    -Path (Join-Path $inspector 'tree.json') `
    -Value $treeStatus `
    -Depth 10

# ------------------------------------------------------------
# git-status.json
# ------------------------------------------------------------

$gitStatus = [ordered]@{
    schema      = 'vsa.inspector.git.v0.1'
    generatedAt = $now
    branch      = "$gitBranch"
    commit      = "$gitCommit"
    dirtyCount  = $changes.Count
    changes     = $changes
    diffStat    = $diffStat
    cachedStat  = $cachedDiffStat
}

Write-JsonAtomic `
    -Path (Join-Path $inspector 'git-status.json') `
    -Value $gitStatus

# ------------------------------------------------------------
# manifest.json
# ------------------------------------------------------------

$manifest = [ordered]@{
    schema      = 'vsa.inspector.manifest.v0.1'
    generatedAt = $now
    mode        = 'READ_ONLY_STATIC_SNAPSHOT'

    endpoints = @(
        '/health.json',
        '/inspector/manifest.json',
        '/inspector/project.json',
        '/inspector/tree.json',
        '/inspector/git-status.json'
    )

    capabilities = [ordered]@{
        health          = $true
        projectMetadata = $true
        projectTree     = $true
        gitStatus       = $true

        fileContents    = $false
        commandExecute  = $false
        writeFiles      = $false
        gitCommit       = $false
        gitPush         = $false
    }
}

Write-JsonAtomic `
    -Path (Join-Path $inspector 'manifest.json') `
    -Value $manifest

Write-Host ''
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' VSA READ-ONLY INSPECTOR v0.1 UPDATED' -ForegroundColor Green
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host "Branch       : $gitBranch"
Write-Host "Commit       : $gitCommit"
Write-Host "Dirty        : $($changes.Count)"
Write-Host "Tree entries : $($entries.Count)"
Write-Host ''
Write-Host 'Endpoints:'
Write-Host '  /health.json'
Write-Host '  /inspector/manifest.json'
Write-Host '  /inspector/project.json'
Write-Host '  /inspector/tree.json'
Write-Host '  /inspector/git-status.json'
