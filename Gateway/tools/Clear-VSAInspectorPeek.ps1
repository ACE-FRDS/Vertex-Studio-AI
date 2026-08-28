param(
    [Parameter(Mandatory=$true)]
    [string]$PeekId
)

$ErrorActionPreference = 'Stop'

if ($PeekId -notmatch '^[a-f0-9]{20}$') {
    throw 'Invalid Peek ID.'
}

$path = Join-Path `
    'G:\Vertex_Project\Vertex_Studio_AI\Gateway\public\inspector\peek' `
    "$PeekId.json"

if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Force
    Write-Host "Deleted Peek: $PeekId" -ForegroundColor Green
}
else {
    Write-Host "Peek not found: $PeekId" -ForegroundColor Yellow
}
