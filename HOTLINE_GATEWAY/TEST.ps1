$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$env:PYTHONPATH=Join-Path $root 'src'
python -m unittest discover -s (Join-Path $root 'tests') -v
