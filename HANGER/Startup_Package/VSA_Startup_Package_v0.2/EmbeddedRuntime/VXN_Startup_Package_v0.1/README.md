# VXN Startup Package v0.1

**Vertex Native (VXN)** is a Vertex-native semantic/execution representation intended to shorten:

`Human Intent -> AI -> Runtime -> CPU / GPU`

This startup package contains editable source for every v0.1 functional domain. The end-to-end life-sign path is implemented and tested:

`Source -> Parse -> Validate -> Optimize -> Execute -> Result`

Example:

```text
const a 1
const b 2
add c a b
print c
halt
```

Expected output: `3`

## Included source domains

- Semantic IR and typed values
- Parser
- Validator
- Constant-fold optimizer
- Deterministic interpreter runtime
- Scheduler / local job queue
- Interface Transport
- Reinforcement Transport
- Capability Registry / Capability on Demand
- Hot Reinforcement staging/activation
- Permission policy
- Observatory telemetry sink
- Memory / file / SQLite-CLI storage adapters
- Package manifest loader
- CPU backend + GPU backend contract
- Natural-language / GUI / voice / diagram ingress envelope
- CLI
- Optional C++ low-level acceleration seam
- DNC / invariants
- RCC baseline
- VCC seed
- Examples and tests

## v0.1 boundary

The package is a **working startup kernel**, not a claim that every future hardware backend is production-complete. GPU execution and embedded SQLite are replaceable contracts in v0.1. The reference runtime, parser, validator, optimizer, storage, scheduler, transport, reinforcement model and CLI are executable source.

## Verify

```bash
cargo check --workspace
cargo test --workspace
cargo run -p vxn-cli -- examples/add.vxn
```
