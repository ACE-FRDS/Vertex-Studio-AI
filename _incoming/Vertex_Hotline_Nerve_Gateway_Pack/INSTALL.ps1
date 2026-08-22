$ErrorActionPreference='Stop'
$packageRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
$mothership='G:\Vertex Protocol\Vertex Project'
$target=Join-Path $mothership 'HOTLINE_GATEWAY'

if(Test-Path $target){
  $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
  $backup=Join-Path $mothership "HOTLINE_GATEWAY.backup-$stamp"
  Write-Host "Backing up existing gateway -> $backup" -ForegroundColor Yellow
  Copy-Item $target $backup -Recurse -Force
}

if(-not (Test-Path $target)){
  New-Item -ItemType Directory -Path $target | Out-Null
}

Copy-Item "$packageRoot\*" $target -Recurse -Force

Write-Host "`n=== BUILD AFTER INSTALL ===" -ForegroundColor Cyan
& "$target\BUILD.ps1"

Write-Host "`n=== INSTALLED ===" -ForegroundColor Green
Write-Host $target
Write-Host "Run:"
Write-Host "  `$env:VERTEX_VCRAS_TOKEN='your-owner-token'"
Write-Host "  & '$target\RUN_GATEWAY.ps1'"
