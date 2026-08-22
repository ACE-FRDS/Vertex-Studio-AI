$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$env:PYTHONPATH=Join-Path $Root "FLEET_ENGINE"
python (Join-Path $Root "FLEET_ENGINE\cli.py") boot "Human enters Vertex World"
