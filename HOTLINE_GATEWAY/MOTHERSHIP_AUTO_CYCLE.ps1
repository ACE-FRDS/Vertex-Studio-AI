param(
    [string]$Token = 'vertex-owner-local-test'
)

$ErrorActionPreference = 'Stop'

$gateway = 'G:\Vertex Protocol\Vertex Project\HOTLINE_GATEWAY'

Write-Host "`n=== MOTHERSHIP AUTO CYCLE ===" -ForegroundColor Cyan

Write-Host "`n[1/4] SNAPSHOT" -ForegroundColor DarkCyan
& "$gateway\MOTHERSHIP_SNAPSHOT.ps1"

Write-Host "`n[2/4] DELTA" -ForegroundColor DarkCyan
& "$gateway\MOTHERSHIP_DELTA.ps1"

Write-Host "`n[3/4] WATCH" -ForegroundColor DarkCyan
& "$gateway\MOTHERSHIP_DELTA_WATCH.ps1"

Write-Host "`n[4/4] DISPATCH" -ForegroundColor DarkCyan
& "$gateway\MOTHERSHIP_MISSION_DISPATCH.ps1" -Token $Token

Write-Host "`n=== AUTO CYCLE COMPLETE ===" -ForegroundColor Green