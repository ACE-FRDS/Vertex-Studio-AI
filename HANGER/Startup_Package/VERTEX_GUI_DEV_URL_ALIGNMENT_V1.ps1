& {
$ErrorActionPreference='Stop'

$startup='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$ui=Join-Path $startup 'VSA_Startup_Package_v0.2\apps\vsa-shell'
$tauri=Join-Path $ui 'src-tauri\tauri.conf.json'
$launcher=Join-Path $startup 'START_VERTEX_GUI_DEV.ps1'
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup="$tauri.$stamp.bak"

Write-Host @'
============================================================
 VERTEX — GUI DEV URL ALIGNMENT V1
 VITE localhost <-> TAURI devUrl
============================================================
'@ -ForegroundColor Cyan

if(-not(Test-Path -LiteralPath $tauri)){
  throw "tauri.conf.json missing: $tauri"
}

$text=[IO.File]::ReadAllText($tauri)

$has127=$text.Contains('http://127.0.0.1:5173')
$hasLocal=$text.Contains('http://localhost:5173')

Write-Host "Tauri config: $tauri"
Write-Host ("127.0.0.1 devUrl present : {0}" -f $has127)
Write-Host ("localhost devUrl present : {0}" -f $hasLocal)

if($has127){
  Copy-Item -LiteralPath $tauri -Destination $backup -Force
  $text=$text.Replace('http://127.0.0.1:5173','http://localhost:5173')
  [IO.File]::WriteAllText($tauri,$text,(New-Object System.Text.UTF8Encoding($false)))
  Write-Host "Backup: $backup" -ForegroundColor DarkGray
  Write-Host 'Tauri devUrl -> http://localhost:5173 : ALIGNED' -ForegroundColor Green
}
elseif($hasLocal){
  Write-Host 'Tauri devUrl already aligned.' -ForegroundColor Green
}
else{
  throw 'Neither expected devUrl was found. Refusing blind mutation.'
}

$verify=[IO.File]::ReadAllText($tauri)
if(-not $verify.Contains('http://localhost:5173')){
  throw 'devUrl verification failed.'
}

if(-not(Test-Path -LiteralPath $launcher)){
  throw "GUI dev launcher missing: $launcher"
}

Write-Host ''
Write-Host 'GUI DEV URL ALIGNMENT: GREEN' -ForegroundColor Green
Write-Host ''
Write-Host 'NEXT:' -ForegroundColor Yellow
Write-Host ('  & "{0}"' -f $launcher) -ForegroundColor White
Write-Host ''
Write-Host 'THE BLINDFOLD STAYS OFF.' -ForegroundColor Cyan
}