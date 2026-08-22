param([Parameter(Mandatory=$true)][string]$Workspace,[string]$Intent="Inspect the workspace, make one safe improvement, build and test it, preserve evidence.",[switch]$Materialize)
$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$env:PYTHONPATH=Join-Path $Root "WORLD_ENGINE"
Write-Host "VERTEX WORLD — FLIGHT"
python -m vertex_world.cli --root $Root providers
$args2=@("-m","vertex_world.cli","--root",$Root,"flight","--workspace",$Workspace,"--intent",$Intent)
if($Materialize){$args2+="--materialize"}
python @args2
