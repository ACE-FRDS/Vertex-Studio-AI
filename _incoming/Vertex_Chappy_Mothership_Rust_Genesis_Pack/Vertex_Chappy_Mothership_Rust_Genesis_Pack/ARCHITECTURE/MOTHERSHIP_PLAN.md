# Mothership construction plan

## Core topology

```text
Chappy / Codex / approved external client
                |
          Transport Adapter
                |
        Vertex Harness API
                |
     +----------+-----------+
     |          |           |
   Policy     Audit      Boot Context
     |          |       VCC/VSP/VMB/CANON
     |          |
     +----- Capability Router --------+
           |       |       |          |
          VUR     ARD     VVE       Runtime
                           |           |
                    Future Overlay   Git/Test/Build
                           |
                      Human Gate
                           |
                      Real Repository
```

## Design rule

The harness may possess strong OS permissions, but **capability policy decides what the agent may request**, and **VVE decides where mutation lands**. OS permission and product permission are separate layers.

## Genesis phases

1. Observation: Mothership state, VUR, ARD, Git inspect.
2. Safe execution: build/test via constrained runner.
3. VVE mutation: create/write changesets only in overlay.
4. Human gate: explicit promotion intent; no implicit Real write.
5. Transport adapters: GitHub, MCP, or other approved bridge.
6. Rich desktop: PTY/ConPTY, GUI automation, virtual explorer, Control Console.
