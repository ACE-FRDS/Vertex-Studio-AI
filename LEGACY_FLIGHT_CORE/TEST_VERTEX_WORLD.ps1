$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$env:PYTHONPATH=Join-Path $Root "WORLD_ENGINE"
python (Join-Path $Root "WORLD_ENGINE\run_tests.py")
