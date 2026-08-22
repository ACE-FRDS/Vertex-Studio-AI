param(
    [int]$WatcherIntervalSeconds = 300,
    [string]$Token = 'vertex-owner-local-test'
)

$ErrorActionPreference = 'Stop'

$root = 'G:\Vertex Protocol\Vertex Project'
$gateway = Join-Path $root 'HOTLINE_GATEWAY'
$stateDir = Join-Path $root 'OBSERVATORY\CURRENT'
$statePath = Join-Path $stateDir 'NERVE_RUNTIME.json'

New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

Write-Host "`n=== VERTEX NERVE START ===" -ForegroundColor Cyan

# 既存起動チェック
if (Test-Path $statePath) {
    try {
        $old = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json

        $gatewayAlive = $false
        $watcherAlive = $false

        if ($old.gateway_pid) {
            $gatewayAlive = $null -ne (Get-Process -Id $old.gateway_pid -ErrorAction SilentlyContinue)
        }

        if ($old.watcher_pid) {
            $watcherAlive = $null -ne (Get-Process -Id $old.watcher_pid -ErrorAction SilentlyContinue)
        }

        if ($gatewayAlive -or $watcherAlive) {
            Write-Host "Existing nerve runtime detected." -ForegroundColor Yellow
            Write-Host "Gateway PID:" $old.gateway_pid
            Write-Host "Watcher PID:" $old.watcher_pid
            exit 0
        }
    }
    catch {
    }
}

Write-Host "`n[1/2] Starting Gateway..." -ForegroundColor DarkCyan

$gatewayArgs = @(
    '-NoExit',
    '-Command',
    "`$env:VERTEX_VCRAS_TOKEN='$Token'; & '$gateway\RUN_GATEWAY.ps1'"
)

$gatewayProcess = Start-Process `
    -FilePath 'powershell.exe' `
    -ArgumentList $gatewayArgs `
    -PassThru

$ready = $false

for($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500

    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8765/health'

        if($health.ok) {
            $ready = $true
            break
        }
    }
    catch {
    }
}

if(-not $ready) {
    Stop-Process -Id $gatewayProcess.Id -Force -ErrorAction SilentlyContinue
    throw 'Gateway did not become ready.'
}

Write-Host "Gateway online:" $health.version -ForegroundColor Green
Write-Host "Gateway PID   :" $gatewayProcess.Id

Write-Host "`n[2/2] Starting Observatory Watcher..." -ForegroundColor DarkCyan

$watcherCommand = @"
& '$gateway\RUN_OBSERVATORY_WATCHER.ps1' `
    -IntervalSeconds $WatcherIntervalSeconds `
    -Token '$Token'
"@

$watcherArgs = @(
    '-NoExit',
    '-Command',
    $watcherCommand
)

$watcherProcess = Start-Process `
    -FilePath 'powershell.exe' `
    -ArgumentList $watcherArgs `
    -PassThru

$runtime = [ordered]@{
    schema        = 'VERTEX_NERVE_RUNTIME'
    version       = '1.0.0'
    started_at    = (Get-Date).ToUniversalTime().ToString('o')
    gateway_pid   = $gatewayProcess.Id
    watcher_pid   = $watcherProcess.Id
    interval_sec  = $WatcherIntervalSeconds
    gateway_url   = 'http://127.0.0.1:8765'
    world_root    = $root
}

[System.IO.File]::WriteAllText(
    $statePath,
    ($runtime | ConvertTo-Json -Depth 10),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Watcher PID   :" $watcherProcess.Id -ForegroundColor Green
Write-Host "Interval      :" $WatcherIntervalSeconds "seconds"

Write-Host "`n=== VERTEX NERVE ONLINE ===" -ForegroundColor Green
Write-Host "Runtime state:" $statePath