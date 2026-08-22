param(
    [string]$Token = 'vertex-owner-local-test'
)

$ErrorActionPreference = 'Stop'

$root       = 'G:\Vertex Protocol\Vertex Project'
$missionDir = Join-Path $root 'OBSERVATORY\MISSIONS'
$gatewayMissionDir = Join-Path $root 'HOTLINE_GATEWAY\STATE\missions'

$missionFile = Get-ChildItem $missionDir -Filter 'delta-*.json' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $missionFile) {
    Write-Host "`n=== MISSION DISPATCH ===" -ForegroundColor Cyan
    Write-Host "NO_PENDING_MISSION" -ForegroundColor DarkGray
    exit 0
}

$mission = Get-Content $missionFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json

if ($mission.state -ne 'PENDING') {
    Write-Host "`n=== MISSION DISPATCH ===" -ForegroundColor Cyan
    Write-Host "NO_PENDING_MISSION" -ForegroundColor DarkGray
    exit 0
}

# ------------------------------------------------------------
# Idempotency check
# ------------------------------------------------------------

$existingGatewayMission = $null

Get-ChildItem $gatewayMissionDir -File -ErrorAction SilentlyContinue |
    ForEach-Object {
        if ($existingGatewayMission) {
            return
        }

        try {
            $gatewayMission = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json

            if ($gatewayMission.payload.source_mission_id -eq $mission.mission_id) {
                $existingGatewayMission = $gatewayMission
            }
        }
        catch {
        }
    }

if ($existingGatewayMission) {

    $mission.state = 'DISPATCHED'

    if (-not $mission.PSObject.Properties['dispatched_at']) {
        $mission |
            Add-Member `
                -NotePropertyName 'dispatched_at' `
                -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o')
    }

    if (-not $mission.PSObject.Properties['gateway_mission_id']) {
        $mission |
            Add-Member `
                -NotePropertyName 'gateway_mission_id' `
                -NotePropertyValue $existingGatewayMission.mission_id
    }

    [System.IO.File]::WriteAllText(
        $missionFile.FullName,
        ($mission | ConvertTo-Json -Depth 30),
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Host "`n=== MISSION DISPATCH ===" -ForegroundColor Cyan
    Write-Host "ALREADY_DISPATCHED" -ForegroundColor Yellow
    Write-Host "Source :" $mission.mission_id
    Write-Host "Gateway:" $existingGatewayMission.mission_id

    exit 0
}

# ------------------------------------------------------------
# New dispatch
# ------------------------------------------------------------

$headers = @{
    'X-Vertex-Owner-Token' = $Token
    'Content-Type'         = 'application/json'
}

$body = @{
    mission_type = $mission.mission_type
    capability   = 'MISSION_SUBMIT'

    payload = @{
        source_mission_id = $mission.mission_id
        events            = $mission.events
        delta             = $mission.delta
    }
} | ConvertTo-Json -Depth 30

$result = Invoke-RestMethod `
    'http://127.0.0.1:8765/mission' `
    -Method Post `
    -Headers $headers `
    -Body $body

$mission.state = 'DISPATCHED'

if (-not $mission.PSObject.Properties['dispatched_at']) {
    $mission |
        Add-Member `
            -NotePropertyName 'dispatched_at' `
            -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o')
}
else {
    $mission.dispatched_at = (Get-Date).ToUniversalTime().ToString('o')
}

if (-not $mission.PSObject.Properties['gateway_mission_id']) {
    $mission |
        Add-Member `
            -NotePropertyName 'gateway_mission_id' `
            -NotePropertyValue $result.mission_id
}
else {
    $mission.gateway_mission_id = $result.mission_id
}

[System.IO.File]::WriteAllText(
    $missionFile.FullName,
    ($mission | ConvertTo-Json -Depth 30),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "`n=== MISSION DISPATCH ===" -ForegroundColor Cyan
Write-Host "DISPATCHED" -ForegroundColor Green
Write-Host "Source :" $mission.mission_id
Write-Host "Gateway:" $result.mission_id
Write-Host "Events :" ($mission.events -join ', ')