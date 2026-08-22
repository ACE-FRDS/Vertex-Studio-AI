# System Map

VCRAS
- Owner-only remote-agent hotline boundary
- request envelope validation
- session / nonce / signature hook
- does not execute shell directly

VCG
- capability policy enforcement
- allowlist dispatch
- audit-first execution
- direct Real Repository writes denied

Hyper Agent Router
- converts request to Mission
- dispatches to relation/query/build/test/vve handlers
- tracks Mission state

ARD Relation Bridge
- aggregates:
  - VUR registry relations
  - VVE ChangeSets
  - Repository state
  - Hyper Agent Mission edges
- exposes dependency/impact queries

Repository Bridge
- read-only Git inspection
- branch / commit / status / diff metadata
- no write / commit / push

VVE Bridge
- read ChangeSets
- create new ChangeSets in approved VVE outbox
- never edits Real Repository

Audit
- append-only JSONL
- actor / mission / capability / decision / result
