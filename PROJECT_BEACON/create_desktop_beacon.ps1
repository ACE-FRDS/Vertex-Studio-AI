param(
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [Parameter(Mandatory=$true)][string]$DisplayName,
  [string]$VertexExe='VertexStudio.exe'
)
$desktop=[Environment]::GetFolderPath('Desktop')
$shortcutPath=Join-Path $desktop "$DisplayName.lnk"
$ws=New-Object -ComObject WScript.Shell
$sc=$ws.CreateShortcut($shortcutPath)
$sc.TargetPath=$VertexExe
$sc.Arguments="--project `"$ProjectId`" --resume"
$sc.WorkingDirectory=Split-Path $VertexExe -Parent
$sc.Save()
Write-Host "Created Project Beacon: $shortcutPath"
