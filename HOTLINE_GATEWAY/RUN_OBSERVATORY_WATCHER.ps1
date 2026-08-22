param(
    [int]$IntervalSeconds = 300,
    [string]$Token = 'vertex-owner-local-test'
)

$ErrorActionPreference = 'Stop'

$gateway = 'G:\Vertex Protocol\Vertex Project\HOTLINE_GATEWAY'
$logDir = 'G:\Vertex Protocol\Vertex Project\OBSERVATORY\LOGS'

New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Write-Host "`n=== OBSERVATORY WATCHER ONLINE ===" -ForegroundColor Green
Write-Host "Interval:" $IntervalSeconds "seconds"
Write-Host "Gateway :" $gateway

while ($true) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPath = Join-Path $logDir "watch-$stamp.log"

    try {
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] AUTO CYCLE" -ForegroundColor Cyan

        & "$gateway\MOTHERSHIP_AUTO_CYCLE.ps1" -Token $Token *>&1 |
            Tee-Object -FilePath $logPath

        Write-Host "Cycle complete." -ForegroundColor DarkGreen
    }
    catch {
        $_ | Out-String | Tee-Object -FilePath $logPath -Append
        Write-Host "Watcher cycle failed. Gateway remains independent." -ForegroundColor Yellow
    }

    Start-Sleep -Seconds $IntervalSeconds
}