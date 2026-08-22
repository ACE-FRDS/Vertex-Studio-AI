# Dynamic Impact Experiment

Target loop:

1. Receive user/agent input.
2. Update the Impact Index before factual search.
3. Select high-impact candidate IDs / relation neighborhoods.
4. Ask VMB to hydrate those neighborhoods from VCC/RDB.
5. Return recall candidates.
6. Observe user/LLM response.
7. Apply Useful / Irrelevant / SurprisingUseful feedback immediately.
8. Persist only slow-changing impact history to the durable layer.

Measure:
- recall latency
- candidate fan-out
- useful recall rate
- irrelevant recall rate
- surprising-useful recall rate
- impact oscillation
- time to re-activate an old topic
- cold-start improvement from durable impact seeds
