param([int]$Worlds=10000)
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$env:PYTHONPATH=Join-Path $Root "FLEET_ENGINE"
python (Join-Path $Root "FLEET_ENGINE\cli.py") simulate $Worlds
