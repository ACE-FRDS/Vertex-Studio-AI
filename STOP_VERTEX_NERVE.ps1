$ErrorActionPreference = 'Stop'

$root = 'G:\Vertex Protocol\Vertex Project'
$statePath = Join-Path $root 'OBSERVATORY\CURRENT\NERVE_RUNTIME.json'

Write-Host "`n=== VERTEX NERVE STOP ===" -ForegroundColor Cyan

if (-not (Test-Path $statePath)) {
    Write-Host "NO_RUNTIME_STATE" -ForegroundColor DarkGray
    exit 0
}

$runtime = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json

$stopped = @()

foreach ($entry in @(
    @{ name='Watcher'; pid=$runtime.watcher_pid },
    @{ name='Gateway'; pid=$runtime.gateway_pid }
)) {
    if (-not $entry.pid) {
        continue
    }

    $proc = Get-Process -Id $entry.pid -ErrorAction SilentlyContinue

    if ($proc) {
        Stop-Process -Id $entry.pid -Force
        $stopped += "$($entry.name):$($entry.pid)"
        Write-Host "$($entry.name) stopped:" $entry.pid -ForegroundColor Green
    }
    else {
        Write-Host "$($entry.name) already stopped:" $entry.pid -ForegroundColor DarkGray
    }
}

Remove-Item $statePath -Force -ErrorAction SilentlyContinue

Write-Host "`n=== VERTEX NERVE OFFLINE ===" -ForegroundColor Green

if ($stopped.Count -gt 0) {
    Write-Host "Stopped:" ($stopped -join ', ')
}