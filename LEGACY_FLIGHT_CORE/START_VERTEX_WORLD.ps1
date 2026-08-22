$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$env:PYTHONPATH=Join-Path $Root "WORLD_ENGINE"
python -m vertex_world.cli --root $Root providers
python -m vertex_world.cli --root $Root status
Write-Host "VSA: http://127.0.0.1:8765"
python -m vertex_world.cli --root $Root ui --port 8765
