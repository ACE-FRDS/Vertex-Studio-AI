# VXN Startup Architecture

```text
Ingress
  -> Parser / Semantic Adapter
  -> VXN IR
  -> Validator
  -> Optimizer
  -> Runtime
       -> Capability Registry
       -> Storage
       -> Transport
       -> Scheduler
       -> Security Policy
       -> Observatory
  -> Backend (CPU / GPU contract / native acceleration seam)
```

Transport is split into **Interface Transport** (schemas/types/capabilities/dependencies/permissions/semantic interfaces) and **Reinforcement Transport** (modules/agents/models/runtimes/UI components/knowledge staged and activated without monolithic replacement).
