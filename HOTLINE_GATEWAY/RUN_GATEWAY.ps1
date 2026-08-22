$ErrorActionPreference='Stop'

$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$env:PYTHONPATH=Join-Path $root 'src'

if(-not $env:VERTEX_VCRAS_TOKEN){
  Write-Host "VERTEX_VCRAS_TOKEN is not set." -ForegroundColor Yellow
  exit 1
}

Write-Host "`n=== GATEWAY START ===" -ForegroundColor Cyan

$quotedRoot = '"' + $root + '"'

$gatewayProcess = Start-Process `
    -FilePath 'python' `
    -ArgumentList "-m vertex_gateway --root $quotedRoot" `
    -PassThru `
    -NoNewWindow

Write-Host "`n=== WAITING FOR GATEWAY ===" -ForegroundColor Cyan

$ready = $false

for($i=0; $i -lt 20; $i++){
    Start-Sleep -Milliseconds 500

    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8765/health'

        if($health.ok){
            $ready = $true
            break
        }
    }
    catch {
    }
}

if(-not $ready){
    throw 'Gateway failed to become ready.'
}

Write-Host "Gateway ready:" $health.version -ForegroundColor Green

Write-Host "`n=== POST-FLIGHT AUTO CYCLE ===" -ForegroundColor Cyan
& "$root\MOTHERSHIP_AUTO_CYCLE.ps1" -Token $env:VERTEX_VCRAS_TOKEN

Write-Host "`n=== GATEWAY ONLINE ===" -ForegroundColor Green
Write-Host "PID:" $gatewayProcess.Id
Write-Host "Listening on http://127.0.0.1:8765"

Wait-Process -Id $gatewayProcess.Id