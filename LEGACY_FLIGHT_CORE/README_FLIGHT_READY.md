# VERTEX WORLD — FLIGHT READY

Verified:
BOOT → Mission Normalize/Decompose → Header/Footer → OpenAI-compatible Cognition →
Workspace Mount → Build/Test → Semantic Revision → VCC/VSP → Repository FSCK →
Failure Recovery → Reboot Continuity.

The build container cannot contact the user's real LM Studio/Ollama.
The exact provider execution path is verified with an in-process OpenAI-compatible mock.

Windows:
.\TEST_VERTEX_WORLD.ps1
.\FLIGHT_VERTEX_WORLD.ps1 -Workspace "C:\path\to\project"

First flight: do not use -Materialize. Review evidence/diffs first.
Then repeat with -Materialize if desired.
