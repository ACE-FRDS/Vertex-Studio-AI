# Correction Report — VSA Startup Package v0.1

## Corrected
- Generic `DNA/` renamed to canonical `DNC/`.
- DNC explicitly defined as **Dynamic Native Code**.
- Added anti-LLM-bias / anti-normalization invariants.
- Preserved separation: DNC != VCC; VCC != VSP.
- Preserved Startup order: StartupSource -> VCC -> VSP -> Repository Evidence -> Mission.
- Embedded VXN package corrected to DNC terminology as well.
- Package manifest now points to canonical DNC.
- Conventional terminology must not silently replace adopted Vertex terminology.

## Verification
This correction is structural/textual. It does not claim a Rust/JS build PASS.
Existing generated source remains subject to Reality Check on the user's development machine.
