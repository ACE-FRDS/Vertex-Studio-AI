param([Parameter(Mandatory=$true)][string]$ProgramSource)
$ErrorActionPreference="Stop"
$ProgramSource=(Resolve-Path $ProgramSource).Path
$RepoRoot=Split-Path -Parent $ProgramSource
$Pkg=Split-Path -Parent $MyInvocation.MyCommand.Path
$Backup=Join-Path $RepoRoot ("_vie_v02_backup_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $Backup|Out-Null
function Overlay([string]$rel){$s=Join-Path $Pkg $rel;$d=Join-Path $RepoRoot $rel;New-Item -ItemType Directory -Force -Path(Split-Path -Parent $d)|Out-Null;if(Test-Path $d){$b=Join-Path $Backup $rel;New-Item -ItemType Directory -Force -Path(Split-Path -Parent $b)|Out-Null;Copy-Item $d $b -Force};Copy-Item $s $d -Force;Write-Host " + $rel"}
Get-ChildItem(Join-Path $Pkg "ProgramSource\crates\vertex-ai-impact")-Recurse -File|%{Overlay($_.FullName.Substring($Pkg.Length).TrimStart('\'))}
Get-ChildItem(Join-Path $Pkg "ProgramSource\apps\vsa-impact-front-lab")-Recurse -File|%{Overlay($_.FullName.Substring($Pkg.Length).TrimStart('\'))}
$cargo=Join-Path $ProgramSource "Cargo.toml";$txt=Get-Content $cargo -Raw
$anchor='    "crates/vertex-ai-memory",'
foreach($m in @('    "crates/vertex-ai-impact",','    "apps/vsa-impact-front-lab",')){if(-not $txt.Contains($m)){$txt=$txt.Replace($anchor,$anchor+"`r`n"+$m)}}
Set-Content $cargo $txt -Encoding utf8
Write-Host "Installed. Backup: $Backup"
