$ErrorActionPreference = 'Stop'

$snapshotDir = 'G:\Vertex Protocol\Vertex Project\OBSERVATORY\SNAPSHOTS'

$files = Get-ChildItem $snapshotDir -Filter 'mothership-*.json' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 2

if ($files.Count -lt 2) {
    throw 'Need at least two snapshots.'
}

$current = Get-Content $files[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
$previous = Get-Content $files[1].FullName -Raw -Encoding UTF8 | ConvertFrom-Json

$repoChanges = @()

foreach ($repo in $current.repositories) {
    $old = $previous.repositories |
        Where-Object { $_.repository_id -eq $repo.repository_id } |
        Select-Object -First 1

    if (-not $old) {
        $repoChanges += [pscustomobject]@{
            repository_id = $repo.repository_id
            change        = 'ADDED'
            branch_before = $null
            branch_after  = $repo.git.branch.stdout
            commit_before = $null
            commit_after  = $repo.git.commit.stdout
            dirty_before  = $null
            dirty_after   = [bool]$repo.git.status.stdout
        }
        continue
    }

    $changed = (
        $old.git.branch.stdout -ne $repo.git.branch.stdout -or
        $old.git.commit.stdout -ne $repo.git.commit.stdout -or
        $old.git.status.stdout -ne $repo.git.status.stdout
    )

    if ($changed) {
        $repoChanges += [pscustomobject]@{
            repository_id = $repo.repository_id
            change        = 'CHANGED'
            branch_before = $old.git.branch.stdout
            branch_after  = $repo.git.branch.stdout
            commit_before = $old.git.commit.stdout
            commit_after  = $repo.git.commit.stdout
            dirty_before  = [bool]$old.git.status.stdout
            dirty_after   = [bool]$repo.git.status.stdout
        }
    }
}

$delta = [ordered]@{
    previous_snapshot = $files[1].FullName
    current_snapshot  = $files[0].FullName

    gateway = [ordered]@{
        before = $previous.gateway.version
        after  = $current.gateway.version
    }

    vur = [ordered]@{
        vcells_before = $previous.vur.vcells
        vcells_after  = $current.vur.vcells
        units_before  = $previous.vur.units
        units_after   = $current.vur.units
        packs_before  = $previous.vur.packs
        packs_after   = $current.vur.packs
    }

    ard = [ordered]@{
        nodes_before = $previous.mothership_graph.nodes.Count
        nodes_after  = $current.mothership_graph.nodes.Count
        edges_before = $previous.mothership_graph.edges.Count
        edges_after  = $current.mothership_graph.edges.Count
    }

    vve = [ordered]@{
        changesets_before = $previous.vve.Count
        changesets_after  = $current.vve.Count
    }

    repositories = $repoChanges
}

Write-Host "`n=== MOTHERSHIP DELTA ===" -ForegroundColor Cyan

$json = $delta | ConvertTo-Json -Depth 20

$currentDir = 'G:\Vertex Protocol\Vertex Project\OBSERVATORY\CURRENT'
$currentPath = Join-Path $currentDir 'MOTHERSHIP_DELTA.json'

New-Item `
    -ItemType Directory `
    -Path $currentDir `
    -Force |
    Out-Null

[System.IO.File]::WriteAllText(
    $currentPath,
    $json,
    [System.Text.UTF8Encoding]::new($false)
)

$json

Write-Host "`nCurrent Delta:" -ForegroundColor Green
Write-Host $currentPath