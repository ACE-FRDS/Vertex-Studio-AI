$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $root
Write-Host "VUR Control Console Preview -> http://127.0.0.1:8787" -ForegroundColor Cyan
python -m http.server 8787 --bind 127.0.0.1
Pop-Location
