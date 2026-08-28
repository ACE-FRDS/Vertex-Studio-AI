#!/usr/bin/env sh
set -eu
cargo check --workspace
cargo test --workspace
cargo run -p vxn-cli -- examples/add.vxn
