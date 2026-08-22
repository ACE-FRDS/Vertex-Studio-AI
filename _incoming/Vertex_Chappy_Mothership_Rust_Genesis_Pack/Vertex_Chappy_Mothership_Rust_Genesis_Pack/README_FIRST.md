# Vertex Chappy Mothership — Rust Genesis Pack

Independent Rust implementation inspired by **general local-agent architecture patterns**: a local harness, constrained command execution, audit, policy gates, state observation, and tool-like capabilities.

It does **not** copy, embed, or redistribute OpenAI/Codex proprietary binaries or source code.

## Vertex doctrine

- **VCC**: history / accumulated record.
- **VSP**: present-position state.
- **VMB**: associative memory bridge / external hippocampus.
- **VUR**: asset repository / hangar inventory.
- **ARD**: relation and dependency graph.
- **VVE**: future-state overlay; AI writes futures here first.
- **Human Gate**: boundary between proposed future and Real Repository.
- **Real Repository**: present reality; direct write is disabled by default.

## What this pack contains

A Cargo workspace with:

- `vertex-core` — mission/capability/domain contracts.
- `vertex-policy` — profile and human-gate policy engine.
- `vertex-audit` — append-only JSONL audit trail.
- `vertex-state` — Mothership/VUR/VCC/VSP/VMB state reader.
- `vertex-git` — non-shell Git inspection layer.
- `vertex-runtime` — constrained executable+args runner with timeout and allowlists.
- `vertex-vve` — VVE changeset and overlay writer.
- `vertex-harness` — orchestration layer.
- `vertex-harnessd` — local HTTP control plane.
- `vertexctl` — CLI client/diagnostics.

## Default safety stance

`config/vertex-harness.toml` binds to `127.0.0.1`, keeps direct Real Repository writes off, and requires Human Gate for promotion-class actions. PowerShell is **not** in the default executable allowlist.

## Windows quick start

```powershell
Set-Location '<unpacked pack>'
.\INSTALL_RUST_WINDOWS.ps1
.\BUILD.ps1
.\RUN.ps1
```

New terminal:

```powershell
.\SMOKE.ps1
```

If Rust is already installed, skip the installer.

## First boarding milestone

`CHAPPY-BOARDING-001` is complete when a client can call `READ_MOTHERSHIP_STATE` through the harness without manually copying PowerShell output.

## Important

This Genesis pack provides the local execution/control plane. It deliberately does not pretend to solve ChatGPT product-side connectivity by itself. GitHub, MCP, connector, or another approved transport can be attached later without redesigning the local Vertex control model.
