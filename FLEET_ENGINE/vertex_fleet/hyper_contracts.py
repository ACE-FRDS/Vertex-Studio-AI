from dataclasses import dataclass, field
from typing import Any, Optional


@dataclass(frozen=True)
class InputSignal:
    """
    Generic ingress signal.

    DHA, Human, LLM, API and Agent adapters may all emit this contract.
    Raw source data remains outside the semantic interpretation layer.
    """

    content: Any
    source: str = "HUMAN"
    modality: str = "TEXT"
    context: dict[str, Any] = field(default_factory=dict)
    evidence: tuple[Any, ...] = field(default_factory=tuple)
    confidence: float = 1.0
    requested_capability: Optional[str] = None


@dataclass(frozen=True)
class SemanticEnvelope:
    """
    Canonical semantic input accepted by HYPER Agent Core.
    """

    intent: str
    source: str
    modality: str
    context: dict[str, Any]
    evidence: tuple[Any, ...]
    confidence: float
    requested_capability: Optional[str] = None


@dataclass(frozen=True)
class CapabilityGrant:
    """
    Capability granted by the mothership.

    HYPER Agent may select from grants.
    HYPER Agent does not own root authority to create or mutate them.
    """

    name: str
    kind: str
    priority: int = 100
    enabled: bool = True
    authority_source: str = "MOTHERSHIP"


@dataclass(frozen=True)
class RoutingDecision:
    decision: str
    capability: Optional[str] = None
    kind: Optional[str] = None
    reason: str = ""


@dataclass(frozen=True)
class HumanGateRequest:
    reason: str
    message: str
    confidence: float
    missing: tuple[str, ...] = field(default_factory=tuple)


@dataclass(frozen=True)
class IngestResult:
    decision: str
    envelope: SemanticEnvelope
    mission: Any = None
    route: Optional[RoutingDecision] = None
    human_gate: Optional[HumanGateRequest] = None
