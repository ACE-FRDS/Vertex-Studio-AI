# VIE v0.2 — Dynamic Impact Index

Rust source package, not a patch.

This revision changes VIE from a rear-side scoring service into a front-facing,
conversation-driven dynamic index.

Architecture:

`Request <-> VIE Dynamic Impact Index <-> VMB <-> VCC/RDB`

Durable impact is retained beside authoritative records as slow historical metadata.
Volatile impact lives in the front layer and changes during the conversation.

v0.2 intentionally leaves semantic affinity injection as the next VMB integration seam:
the Impact layer must not pretend it knows factual content by itself.
