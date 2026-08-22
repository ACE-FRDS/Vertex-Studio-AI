param([string]$Token='vertex-owner-local-test')
$ErrorActionPreference='Stop'
Set-Location $PSScriptRoot
$env:VERTEX_CHAPPY_TOKEN=$Token
$env:RUST_LOG='vertex_harnessd=info,tower_http=info'
& cargo run -p vertex-harnessd --release -- --config "$PSScriptRoot\config\vertex-harness.toml"
