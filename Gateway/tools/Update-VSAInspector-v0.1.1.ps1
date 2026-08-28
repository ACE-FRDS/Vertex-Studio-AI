$ErrorActionPreference = 'Stop'

$project = 'G:\Vertex_Project\Vertex_Studio_AI'
$active  = Join-Path $project 'HANGER\Startup_Package\VSA_Startup_Package_v0.2'
$public  = Join-Path $project 'Gateway\public'
$inspector = Join-Path $public 'inspector'

function Write-JsonAtomic {
    param(
        [string]$Path,
        $Value,
        [int]$Depth = 12
    )

    $tmp = "$Path.tmp"

    $Value |
        ConvertTo-Json -Depth $Depth |
        Set-Content -LiteralPath $tmp -Encoding UTF8

    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

$now = (Get-Date).ToString('o')

# ============================================================
# SERVICES
# ============================================================

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

# ============================================================
# GIT
# ============================================================

$gitBranch = (& git -C $project branch --show-current 2>$null)
$gitCommit = (& git -C $project rev-parse --short HEAD 2>$null)

$gitRaw = @(
    & git -C $project status --porcelain=v1 2>$null
)

$changes = @()

foreach ($line in $gitRaw) {

    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    $status = if ($line.Length -ge 2) {
        $line.Substring(0,2)
    }
    else {
        $line
    }

    $path = if ($line.Length -gt 3) {
        $line.Substring(3)
    }
    else {
        ''
    }

    $changes += [ordered]@{
        status = $status
        path   = $path
    }
}

# ============================================================
# ACTIVE WORKSPACE TREE
# ============================================================

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

$denyPatterns = @(
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

$entries = New-Object System.Collections.Generic.List[object]

$maxDepth = 8
$maxItems = 5000

function Test-DeniedFile {
    param([string]$Name)

    foreach ($pattern in $denyPatterns) {
        if ($Name -like $pattern) {
            return $true
        }
    }

    return $false
}

function Add-ActiveTree {
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
            $active,
            $item.FullName
        ) -replace '\\','/'

        $entries.Add(
            [ordered]@{
                path = $relative
                type = if ($item.PSIsContainer) {
                    'directory'
                }
                else {
                    'file'
                }

                size = if ($item.PSIsContainer) {
                    $null
                }
                else {
                    $item.Length
                }

                lastModified = $item.LastWriteTime.ToString('o')
            }
        )

        if ($item.PSIsContainer -and $Depth -lt $maxDepth) {
            Add-ActiveTree `
                -Directory $item.FullName `
                -Depth ($Depth + 1)
        }
    }
}

if (Test-Path $active) {
    Add-ActiveTree -Directory $active -Depth 0
}

# ============================================================
# WORKSPACE MARKERS
# ============================================================

$markers = @(
    $entries |
        Where-Object {
            $_.type -eq 'file' -and (
                $_.path -match '(^|/)Cargo\.toml$' -or
                $_.path -match '(^|/)package\.json$' -or
                $_.path -match '(^|/)vite\.config\.' -or
                $_.path -match '(^|/)tauri\.conf\.json$'
            )
        } |
        Select-Object -First 150
)

# ============================================================
# HEALTH
# ============================================================

$health = [ordered]@{
    probe         = 'VSA-GATEWAY'
    inspector     = 'Ready'
    version       = '0.1.1'
    generatedAt   = $now
    cloudflared   = if ($cloudflared) {
        $cloudflared.Status.ToString()
    }
    else {
        'NotFound'
    }
    iisSite       = $iisState
    activeWorkspace = Test-Path $active
}

Write-JsonAtomic `
    -Path (Join-Path $public 'health.json') `
    -Value $health

# ============================================================
# PROJECT
# ============================================================

$projectStatus = [ordered]@{
    schema      = 'vsa.inspector.project.v0.1.1'
    generatedAt = $now

    project = [ordered]@{
        name = 'Vertex Studio AI'
        root = 'VSA_ROOT'
    }

    activeWorkspace = [ordered]@{
        name   = 'VSA_Startup_Package_v0.2'
        root   = 'VSA_ACTIVE_WORKSPACE'
        exists = Test-Path $active
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

    workspaceMarkers = $markers
}

Write-JsonAtomic `
    -Path (Join-Path $inspector 'project.json') `
    -Value $projectStatus

# ============================================================
# ACTIVE TREE
# ============================================================

$tree = [ordered]@{
    schema      = 'vsa.inspector.active-tree.v0.1.1'
    generatedAt = $now
    workspace   = 'VSA_Startup_Package_v0.2'
    maxDepth    = $maxDepth
    count       = $entries.Count
    truncated   = ($entries.Count -ge $maxItems)
    entries     = $entries
}

Write-JsonAtomic `
    -Path (Join-Path $inspector 'active-tree.json') `
    -Value $tree `
    -Depth 10

# ============================================================
# GIT STATUS
# ============================================================

$gitStatus = [ordered]@{
    schema      = 'vsa.inspector.git.v0.1.1'
    generatedAt = $now
    branch      = "$gitBranch"
    commit      = "$gitCommit"
    dirtyCount  = $changes.Count
    changes     = $changes
}

Write-JsonAtomic `
    -Path (Join-Path $inspector 'git-status.json') `
    -Value $gitStatus

# ============================================================
# MANIFEST
# ============================================================

$manifest = [ordered]@{
    schema      = 'vsa.inspector.manifest.v0.1.1'
    generatedAt = $now
    mode        = 'READ_ONLY_ACTIVE_WORKSPACE'

    endpoints = @(
        '/health.json',
        '/inspector/manifest.json',
        '/inspector/project.json',
        '/inspector/active-tree.json',
        '/inspector/git-status.json'
    )

    capabilities = [ordered]@{
        health          = $true
        projectMetadata = $true
        activeTree      = $true
        gitStatus       = $true

        fileContents    = $false
        commandExecute  = $false
        writeFiles      = $false
        gitCommit       = $false
        gitPush         = $false
    }

    security = [ordered]@{
        absoluteHostPathsExposed = $false
        secretsExposed           = $false
        arbitraryFileRead        = $false
    }
}

Write-JsonAtomic `
    -Path (Join-Path $inspector 'manifest.json') `
    -Value $manifest

# Remove obsolete broad-tree output if present.
$oldTree = Join-Path $inspector 'tree.json'

if (Test-Path $oldTree) {
    Remove-Item $oldTree -Force
}

Write-Host ''
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' VSA INSPECTOR v0.1.1 ACTIVE WORKSPACE READY' -ForegroundColor Green
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host "Workspace    : VSA_Startup_Package_v0.2"
Write-Host "Branch       : $gitBranch"
Write-Host "Commit       : $gitCommit"
Write-Host "Dirty        : $($changes.Count)"
Write-Host "Tree entries : $($entries.Count)"
Write-Host ''
Write-Host 'Endpoints:'
Write-Host '  /health.json'
Write-Host '  /inspector/manifest.json'
Write-Host '  /inspector/project.json'
Write-Host '  /inspector/active-tree.json'
Write-Host '  /inspector/git-status.json'
