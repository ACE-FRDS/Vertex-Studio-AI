param(
    [string]$Token = 'vertex-owner-local-test'
)

$ErrorActionPreference = 'Stop'

$headers = @{
    'X-Vertex-Owner-Token' = $Token
    'Content-Type'         = 'application/json'
}

function Invoke-VertexMission {
    param(
        [string]$Type,
        [string]$Capability,
        [hashtable]$Payload = @{}
    )

    $body = @{
        mission_type = $Type
        capability   = $Capability
        payload      = $Payload
    } | ConvertTo-Json -Depth 20

    Invoke-RestMethod `
        'http://127.0.0.1:8765/mission' `
        -Method Post `
        -Headers $headers `
        -Body $body
}

Write-Host "`n=== VERTEX MOTHERSHIP SNAPSHOT ===" -ForegroundColor Cyan

$health = Invoke-RestMethod 'http://127.0.0.1:8765/health'

$capabilities = Invoke-RestMethod `
    'http://127.0.0.1:8765/capabilities' `
    -Headers $headers

$vur = Invoke-RestMethod `
    'http://127.0.0.1:8765/vur/status' `
    -Headers $headers

$repositories = Invoke-VertexMission `
    -Type 'REPOSITORY_INSPECT' `
    -Capability 'GIT_INSPECT'

$ard = Invoke-VertexMission `
    -Type 'RELATION_QUERY' `
    -Capability 'QUERY_RELATIONS' `
    -Payload @{
        asset_id  = 'project://vertex-studio/mothership'
        mode      = 'impact'
        max_depth = 8
    }

$vve = Invoke-VertexMission `
    -Type 'VVE_INSPECT' `
    -Capability 'READ_VVE'

$snapshot = [ordered]@{
    captured_at = (Get-Date).ToUniversalTime().ToString('o')

    gateway = $health

    capabilities = $capabilities.enabled

    vur = $vur

    repositories = $repositories.result.repositories

    mothership_graph = $ard.result

    vve = $vve.result.changesets
}

$outDir = 'G:\Vertex Protocol\Vertex Project\OBSERVATORY\SNAPSHOTS'

New-Item `
    -ItemType Directory `
    -Path $outDir `
    -Force |
    Out-Null

$outPath = Join-Path `
    $outDir `
    ('mothership-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

$json = $snapshot | ConvertTo-Json -Depth 40

[System.IO.File]::WriteAllText(
    $outPath,
    $json,
    [System.Text.UTF8Encoding]::new($false)
)

$currentDir = 'G:\Vertex Protocol\Vertex Project\OBSERVATORY\CURRENT'
$currentPath = Join-Path $currentDir 'MOTHERSHIP_STATE.json'

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

Write-Host "`nGateway :" $health.version
Write-Host "VCells  :" $vur.vcells
Write-Host "Units   :" $vur.units
Write-Host "Repos   :" $repositories.result.repositories.Count
Write-Host "Nodes   :" $ard.result.nodes.Count
Write-Host "Edges   :" $ard.result.edges.Count
Write-Host "VVE CS  :" $vve.result.changesets.Count

Write-Host "`nSnapshot:" -ForegroundColor Green
Write-Host $outPath