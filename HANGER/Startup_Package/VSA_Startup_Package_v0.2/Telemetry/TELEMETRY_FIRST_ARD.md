# Telemetry-first ARD v0.2

Canonical principles:

> **Reporting should be telemetry, not literature.**
>
> **Reporting is a view over telemetry.**

Worker time is for work. Routine PASS missions must not spend model tokens writing prose that the runtime can observe deterministically.

## Default path

Mission -> Worker execution -> System observation -> Machine telemetry -> next Mission

System observation should collect, when available:

- mission/work-unit ID
- Worker / Model / Role
- start/end/duration
- changed files / diff hash
- build/check/test result
- process exit status
- retries
- scope violations
- Human interventions
- token/prompt units
- VRAM/RAM/CPU evidence
- blocker/evidence references

## Report escalation

1. **FAST ACK** — routine PASS; compact machine representation only.
2. **EXCEPTION REPORT** — FAIL/BLOCKED/UNKNOWN, scope violation, new dependency, contradictory evidence.
3. **HUMAN GATE REPORT** — irreversible architecture/security/publication/destructive actions.

Narrative Japanese/English reports are generated as a **view** only when a Human requests them or escalation requires them.

## Anti-pattern

Do not force every 2B/4B/8B Worker to spend inference budget explaining work that Git, compiler, test runner, filesystem, scheduler and Observatory can measure directly.
