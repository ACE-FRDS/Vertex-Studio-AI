# Threat model — Genesis

## Protect

- Real Repository integrity.
- VUR/VCC/VSP/VMB/CANON history.
- Git credentials and secrets.
- Owner workstation.
- Audit continuity.

## Default controls

- bind localhost only;
- bearer token required by server when configured;
- executable allowlist;
- cwd must be under configured roots;
- no shell-string execution API;
- command timeout;
- VVE writes confined to VVE root;
- Real Repository write disabled by default;
- promotion requires Human Gate;
- append-only audit JSONL.

## Not yet an OS sandbox

Genesis is a policy-controlled harness, not a security boundary equivalent to an OS sandbox. Add Windows restricted tokens/AppContainer/job objects or a dedicated low-privilege service account before enabling broad command execution.
