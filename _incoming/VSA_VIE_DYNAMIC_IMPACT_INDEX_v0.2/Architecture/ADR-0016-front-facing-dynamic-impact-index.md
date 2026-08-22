# ADR-0016 — Front-facing Dynamic Impact Index

## Decision

Impact is moved to the front of the recall path.

`Request <-> Dynamic Impact Index <-> VMB <-> VCC/RDB`

The dynamic layer is mutable and uncertain. The durable factual layer remains authoritative.

## Dual impact

The durable RDB stores slow-changing impact metadata:
- base impact
- historical impact
- explicit human impact
- maximum observed impact
- last impact timestamp

The front layer stores volatile values:
- current impact
- context impact
- activation heat
- relation impact
- confidence
- decay

The durable values seed the volatile index at startup. Conversation changes the volatile
index immediately. Useful/irrelevant recall feedback updates both the volatile layer and
slow historical impact without rewriting factual content.

## Invariant

Impact may be wrong.
Facts must not become wrong because Impact was wrong.
