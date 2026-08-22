$ErrorActionPreference='Stop'
if (Get-Command cargo -ErrorAction SilentlyContinue) {
  Write-Host "Rust already installed:" -ForegroundColor Green
  rustc --version
  cargo --version
  exit 0
}
Write-Host "Installing Rust via rustup (official installer)..." -ForegroundColor Cyan
$uri='https://win.rustup.rs/x86_64'
$out=Join-Path $env:TEMP 'rustup-init.exe'
Invoke-WebRequest $uri -OutFile $out
& $out -y --default-toolchain stable --profile minimal
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
rustc --version
cargo --version
