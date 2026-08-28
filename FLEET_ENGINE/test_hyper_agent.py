import pathlib
import sys
from dataclasses import FrozenInstanceError

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(
    0,
    str(ROOT / "FLEET_ENGINE"),
)

from vertex_fleet.hyper_agent import HyperAgent
from vertex_fleet.hyper_contracts import (
    CapabilityGrant,
    InputSignal,
)
from vertex_fleet.world import VertexWorld


# ------------------------------------------------------------
# 1. Legacy compile stays compatible
# ------------------------------------------------------------

legacy = HyperAgent()

mission = legacy.compile(
    "Preserve existing compile path",
    {"source": "legacy"},
)

assert mission.intent == "Preserve existing compile path"
assert len(mission.tasks) == 4


# ------------------------------------------------------------
# 2. Human text ingress -> Mission
# ------------------------------------------------------------

result = legacy.ingest(
    "Build a solution without shrinking intent"
)

assert result.decision == "PASS"
assert result.mission is not None
assert result.mission.intent == (
    "Build a solution without shrinking intent"
)
assert result.envelope.source == "HUMAN"
assert result.envelope.modality == "TEXT"


# ------------------------------------------------------------
# 3. Low confidence -> Human Gate
# ------------------------------------------------------------

low = legacy.ingest(
    InputSignal(
        content="Maybe this means something",
        confidence=0.20,
    )
)

assert low.decision == "HUMAN_GATE"
assert low.mission is None
assert low.human_gate.reason == "low_confidence"


# ------------------------------------------------------------
# 4. Missing intent -> Human Gate
# ------------------------------------------------------------

missing = legacy.ingest(
    InputSignal(
        content="",
        confidence=1.0,
    )
)

assert missing.decision == "HUMAN_GATE"
assert missing.human_gate.reason == "intent_missing"


# ------------------------------------------------------------
# 5. Mothership authorized capability
# ------------------------------------------------------------

device_grant = CapabilityGrant(
    name="device-mini-llm",
    kind="DEVICE_LLM",
    priority=10,
)

authorized = HyperAgent(
    capability_grants=[
        device_grant,
    ]
)

allowed = authorized.ingest(
    InputSignal(
        content="Summarize this capture",
        requested_capability="device-mini-llm",
    )
)

assert allowed.decision == "PASS"
assert allowed.route.capability == "device-mini-llm"
assert allowed.route.kind == "DEVICE_LLM"


# ------------------------------------------------------------
# 6. Unauthorized capability cannot be selected
# ------------------------------------------------------------

denied = authorized.ingest(
    InputSignal(
        content="Use a forbidden brain",
        requested_capability="unknown-30b",
    )
)

assert denied.decision == "DENIED"
assert denied.mission is None


# ------------------------------------------------------------
# 7. Non-mothership grants are rejected
# ------------------------------------------------------------

rogue_grant = CapabilityGrant(
    name="rogue-brain",
    kind="EXTERNAL_LLM",
    authority_source="HYPER_AGENT",
)

rogue = HyperAgent(
    capability_grants=[
        rogue_grant,
    ]
)

rogue_result = rogue.ingest(
    InputSignal(
        content="Use rogue brain",
        requested_capability="rogue-brain",
    )
)

assert rogue_result.decision == "DENIED"


# ------------------------------------------------------------
# 8. Capability grants themselves are immutable
# ------------------------------------------------------------

frozen = False

try:
    device_grant.name = "mutated"
except FrozenInstanceError:
    frozen = True

assert frozen


# HYPER Agent exposes no root mutation API.
assert not hasattr(
    authorized,
    "register_capability",
)

assert not hasattr(
    authorized,
    "replace_brain",
)

assert not hasattr(
    authorized,
    "remove_capability",
)


# ------------------------------------------------------------
# 9. Existing VertexWorld flow still operates
# ------------------------------------------------------------

world = VertexWorld()

world_result = world.boot(
    "Backward compatibility test"
)

assert world_result["gate"]["decision"] == "PASS"
assert world_result["execution"]["ok"]


print("PASS HYPER AGENT HARDENING v0.1")
print(
    {
        "legacy_tasks": len(mission.tasks),
        "human_ingress": result.decision,
        "low_confidence": low.decision,
        "unauthorized": denied.decision,
        "authorized_capability":
            allowed.route.capability,
        "world_execution":
            world_result["execution"]["ok"],
    }
)
