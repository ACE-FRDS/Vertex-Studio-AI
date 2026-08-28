#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/../ProgramSource"
cargo check --workspace
cargo test --workspace
cargo run -p vsa-cli -- demo
