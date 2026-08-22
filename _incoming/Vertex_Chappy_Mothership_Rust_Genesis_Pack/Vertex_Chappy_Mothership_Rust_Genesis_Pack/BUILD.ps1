$ErrorActionPreference='Stop'
Set-Location $PSScriptRoot
Write-Host "=== RUST TOOLCHAIN ===" -ForegroundColor Cyan
rustc --version
cargo --version
Write-Host "=== FORMAT CHECK ===" -ForegroundColor Cyan
cargo fmt --all -- --check
Write-Host "=== CLIPPY ===" -ForegroundColor Cyan
cargo clippy --workspace --all-targets -- -D warnings
Write-Host "=== TEST ===" -ForegroundColor Cyan
cargo test --workspace
Write-Host "=== RELEASE BUILD ===" -ForegroundColor Cyan
cargo build --workspace --release
Write-Host "BUILD PASS" -ForegroundColor Green
