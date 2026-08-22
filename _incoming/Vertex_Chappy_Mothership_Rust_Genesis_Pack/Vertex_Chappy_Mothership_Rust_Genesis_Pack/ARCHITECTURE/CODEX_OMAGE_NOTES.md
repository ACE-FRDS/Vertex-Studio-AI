# Codex homage notes

The provided reference archive was used only to observe broad architectural patterns visible in a packaged desktop application: separate command/runtime helpers, PTY/terminal support, sandbox-related components, and computer-use components.

This project is an **independent implementation**. It does not extract or incorporate proprietary executables, source, protocol secrets, or private implementation details.

Borrowed ideas at the pattern level:

- separate local harness from model reasoning;
- separate command execution from UI;
- constrained execution environment;
- explicit approval/policy boundaries;
- PTY/terminal abstraction as an optional future layer;
- independent audit and state persistence.

Vertex-specific additions:

- VVE future overlay;
- VUR asset circulation;
- ARD relation graph;
- VCC/VSP/VMB boot context;
- Human Gate as the Real boundary.
