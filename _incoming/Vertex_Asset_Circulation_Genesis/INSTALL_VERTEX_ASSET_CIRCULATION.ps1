$ErrorActionPreference='Stop'
$packageRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
$mothership='G:\Vertex Protocol\Vertex Project'

$targets=@('VUR','VVE','REPOSITORY_BRIDGE','CONNECTORS','PROJECT_BEACON','MAIN_CONSOLE','HYPER_AGENT_CHAT','DESIGN_SYSTEM','EMULATOR','TESTS','ARCHITECTURE')

foreach($name in $targets){
  $src=Join-Path $packageRoot $name
  if(-not (Test-Path $src)){ continue }
  $dst=Join-Path $mothership $name

  if(Test-Path $dst){
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup=Join-Path $mothership "$name.backup-$stamp"
    Write-Host "Backing up $name -> $backup" -ForegroundColor Yellow
    Copy-Item $dst $backup -Recurse -Force
  }

  if(-not (Test-Path $dst)){ New-Item -ItemType Directory -Path $dst | Out-Null }
  Copy-Item "$src\*" $dst -Recurse -Force
}

Write-Host "`n=== VERTEX ASSET CIRCULATION INSTALLED ===" -ForegroundColor Green
Get-ChildItem $mothership -Directory |
  Where-Object { $_.Name -in $targets } |
  Select-Object Name

Write-Host "`nPreview:" -ForegroundColor Cyan
Write-Host "  .\VUR\CONTROL\preview\START_PREVIEW.ps1"

Write-Host "`nVUR status:" -ForegroundColor Cyan
$env:PYTHONPATH="$mothership\VUR\SOURCE"
python -m vur.cli --root "$mothership\VUR" status
