# VVE ↔ GitHub bridge protocol

Purpose: let ChatGPT use its GitHub write surface without giving it direct Real Repository mutation semantics.

1. Chappy writes a proposal to the **VVE GitHub repository/branch**.
2. Local harness observes/fetches that proposal.
3. Proposal becomes a local VVE ChangeSet.
4. Build/Test/Simulation run against isolated overlay/worktree.
5. Human Gate emits an approval record.
6. Promotion adapter materializes the approved state into Real Repository.

The GitHub repository is a transport/replication surface. VVE remains the semantic owner of future state.

Suggested immutable envelope:

```json
{
  "schema": "VERTEX_VVE_GITHUB_ENVELOPE",
  "version": "1.0.0",
  "proposal_id": "proposal://...",
  "source": "chappy",
  "target_project": "project://vertex-studio/mothership",
  "base_commit": "...",
  "files": [],
  "requested_checks": ["build", "test"],
  "real_repository_write": false,
  "human_gate_required": true
}
```
