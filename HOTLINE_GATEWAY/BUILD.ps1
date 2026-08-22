$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$env:PYTHONPATH=Join-Path $root 'src'

Write-Host "=== PYTHON ===" -ForegroundColor Cyan
python --version

Write-Host "`n=== COMPILE ===" -ForegroundColor Cyan
python -m compileall -q (Join-Path $root 'src')

Write-Host "`n=== TEST ===" -ForegroundColor Cyan
python -m unittest discover -s (Join-Path $root 'tests') -v

Write-Host "`nBUILD PASS" -ForegroundColor Green
