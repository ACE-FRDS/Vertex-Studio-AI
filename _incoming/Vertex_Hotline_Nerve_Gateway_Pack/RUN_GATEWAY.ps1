$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$env:PYTHONPATH=Join-Path $root 'src'

if(-not $env:VERTEX_VCRAS_TOKEN){
  Write-Host "VERTEX_VCRAS_TOKEN is not set." -ForegroundColor Yellow
  Write-Host "Example:"
  Write-Host "  `$env:VERTEX_VCRAS_TOKEN='replace-with-owner-token'"
  exit 1
}

python -m vertex_gateway --root $root
