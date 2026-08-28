# ARD Telemetry Invariants

1. Worker Output and Report Output are separate concepts.
2. Routine reporting is system telemetry, not Worker-authored literature.
3. PASS must use the smallest sufficient acknowledgement.
4. FAIL/BLOCKED/UNKNOWN escalates with evidence.
5. Human Gate decisions receive Human-readable context.
6. Compiler/test/diff/filesystem/runtime evidence outranks Worker self-report.
7. Human-readable reports are projections/views over retained telemetry whenever possible.
8. Telemetry collection must not become a new hot-path bottleneck.
9. Large Worker parties must not multiply narrative reporting cost linearly.
10. MNL may render telemetry into Japanese for Humans without forcing Japanese narrative through every Worker.
