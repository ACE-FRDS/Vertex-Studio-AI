# Vertex Live Flight Panel

Formal VertexHub package for the VSA Editor Live Flight telemetry surface.

## Package

- ID: `vertex.live-flight-panel`
- Version: `1.0.0`
- Kind: `ui.component`
- Scope: `vsa.editor`
- Runtime: Vue 3 + Tauri 2
- Telemetry: `vertex.mothership.live-session.v1`

## Runtime boundary

VertexHub does **not** sit in the live control path.

`Mothership -> Runtime Bus -> Tauri IPC -> Live Flight Panel`

VertexHub stores and verifies the reusable component, contract, and distribution metadata.

## Safety

The package is read-only with respect to Mothership control state. It consumes only:

- `vertex_live_session_latest`
- `vertex_live_session_tail`

It does not create or mutate a `FleetControllerSession`.