$ErrorActionPreference = 'Stop'

$deltaPath = 'G:\Vertex Protocol\Vertex Project\OBSERVATORY\CURRENT\MOTHERSHIP_DELTA.json'
$missionDir = 'G:\Vertex Protocol\Vertex Project\OBSERVATORY\MISSIONS'

if (-not (Test-Path $deltaPath)) {
    throw 'MOTHERSHIP_DELTA.json not found'
}

$delta = Get-Content $deltaPath -Raw -Encoding UTF8 | ConvertFrom-Json

$events = @()

if ($delta.vur.vcells_before -ne $delta.vur.vcells_after -or
    $delta.vur.units_before  -ne $delta.vur.units_after  -or
    $delta.vur.packs_before  -ne $delta.vur.packs_after) {

    $events += 'VUR_CHANGED'
}

if ($delta.ard.nodes_before -ne $delta.ard.nodes_after -or
    $delta.ard.edges_before -ne $delta.ard.edges_after) {

    $events += 'ARD_CHANGED'
}

if ($delta.vve.changesets_before -ne $delta.vve.changesets_after) {
    $events += 'VVE_CHANGED'
}

if ($delta.repositories.Count -gt 0) {
    $events += 'REPOSITORY_CHANGED'
}

if ($events.Count -eq 0) {
    Write-Host "`n=== MOTHERSHIP WATCH ===" -ForegroundColor Cyan
    Write-Host "NO_CHANGE" -ForegroundColor DarkGray
    exit 0
}

New-Item -ItemType Directory -Path $missionDir -Force | Out-Null

$missionId = 'mission://observatory/delta/' + [guid]::NewGuid().ToString()

$mission = [ordered]@{
    schema       = 'VERTEX_OBSERVATORY_MISSION'
    version      = '1.0.0'
    mission_id   = $missionId
    mission_type = 'MOTHERSHIP_CHANGE_REVIEW'
    capability   = 'MISSION_SUBMIT'
    actor        = 'observatory'
    created_at   = (Get-Date).ToUniversalTime().ToString('o')
    state        = 'PENDING'
    events       = $events
    delta        = $delta
}

$outPath = Join-Path $missionDir (
    'delta-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json'
)

$json = $mission | ConvertTo-Json -Depth 30

[System.IO.File]::WriteAllText(
    $outPath,
    $json,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "`n=== MOTHERSHIP WATCH ===" -ForegroundColor Cyan
Write-Host "MISSION_CREATED" -ForegroundColor Green
Write-Host "Events :" ($events -join ', ')
Write-Host "Mission:" $missionId
Write-Host "File   :" $outPath