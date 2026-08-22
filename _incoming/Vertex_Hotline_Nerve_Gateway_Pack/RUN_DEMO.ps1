$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$env:PYTHONPATH=Join-Path $root 'src'

if(-not $env:VERTEX_VCRAS_TOKEN){
  $env:VERTEX_VCRAS_TOKEN='vertex-demo-owner-token'
}

Write-Host "Starting Gateway on 127.0.0.1:8765" -ForegroundColor Cyan
python -m vertex_gateway --root $root
