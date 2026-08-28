# VSA Startup Package v0.2 — Telemetry-first ARD / Vertex Canonical Full Source

> **ANTI-LLM-BIAS CONTRACT:** This package must preserve Vertex-native concepts even when a conventional IDE/runtime vocabulary would be more familiar to a model.

> **DNC = Dynamic Native Code. VCC != DNC. VXN != generic language. RCC != plugin. ARD != chat loop.**


**VSA = Vertex Studio AI**

A source-complete startup package for the "giant mothership" concept:

> **Big Product, Small Core, Playable Architecture.**

VSA is intended to combine the useful development experiences of:

- FileMaker
- Visual Studio / JetBrains / VS Code / Cursor
- Dreamweaver
- Fireworks
- Figma / Adobe XD
- AI/ARD-assisted local development

without forcing humans to think in the old frontend/backend split.

## Human-facing concepts

VSA presents:

- Presentation
- Data
- Behavior
- State
- Permission
- Validation
- Capability

and lets Runtime/Capability Placement decide whether execution belongs in:

- Browser
- Desktop
- Server
- Edge
- Local AI runtime

## Startup package meaning

This package includes source for every v0.1 subsystem and explicit source/contracts for the larger future-facing capabilities.
It does **not** claim that the entire long-term VSA product is already production-complete.

The package is a **source-complete embryonic mothership**:
working deterministic core slices + visible extension seams + DNC + continuity seeds.

## v0.1 life signs

Rust workspace:

```bash
cargo check --workspace
cargo test --workspace
cargo run -p vsa-cli -- demo
```

Frontend source is included under:

`apps/vsa-shell`

The frontend is intentionally source-only in this package; install JS dependencies before building it.

## Major included domains

- Shared Foundation
- Vertex Definition / `.vtxs`-style solution model
- Schema / Data Graph / Relation Intelligence
- Layout / Visual Designer model
- Script Workspace semantic steps
- Theme / Asset / Report / Document / Mind Map source models
- Static Website / Dynamic Website / Web App project generation
- Capability Placement
- AI Provider / Model / Role contract layer
- ARD Mission IR / decomposition / scheduling / results
- MNL Mission Normalization Layer
- RCC Rulebook Custom Cartridge
- Observatory telemetry
- VCC / VSP continuity
- Project Convergence Blueprint
- Cartridge runtime contracts
- Drone mission capsule
- Developer Portfolio / Quest / RPG status
- Mother-ship facilities model
- Security / Human Gate / No Fake Completion
- VXN source package embedded as a sibling runtime seed

## v0.2 Telemetry-first ARD

Routine Worker prose is removed from the hot path. System-observed telemetry is canonical; Human-readable reports are generated views and exceptions. See `Telemetry/TELEMETRY_FIRST_ARD.md`.
