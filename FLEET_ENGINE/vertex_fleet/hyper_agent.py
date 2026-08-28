from typing import Any

from .contracts import Mission
from .hyper_contracts import (
    CapabilityGrant,
    HumanGateRequest,
    IngestResult,
    InputSignal,
    RoutingDecision,
    SemanticEnvelope,
)


class HyperAgent:
    """
    Canonical HYPER Agent Core.

    Human -> World semantic ingress.
    Expands intent without silently shrinking it.

    The Core may SELECT mothership-granted capabilities.
    It does not own root authority to register, remove or replace brains.
    """

    def __init__(
        self,
        capability_grants=None,
        confidence_threshold: float = 0.65,
    ):
        self._capability_grants = tuple(
            capability_grants or ()
        )

        threshold = float(confidence_threshold)

        if threshold < 0.0:
            threshold = 0.0
        elif threshold > 1.0:
            threshold = 1.0

        self._confidence_threshold = threshold

    @property
    def capability_grants(self):
        """
        Read-only view of grants supplied by mothership authority.
        """
        return self._capability_grants

    @property
    def confidence_threshold(self):
        return self._confidence_threshold

    def compile(self, intent, world_context):
        """
        Existing Mission compiler.

        Kept backward-compatible intentionally.
        """

        m = Mission(
            intent=intent,
            context=world_context,
        )

        m.tasks = [
            {
                "role": "Navigator",
                "op": "context_reconstruction",
                "header": {
                    "scope": "world",
                    "authority": "READ",
                },
                "footer": {
                    "evidence": True,
                },
            },
            {
                "role": "Architect",
                "op": "semantic_plan",
                "header": {
                    "scope": "mission",
                    "authority": "PLAN",
                },
                "footer": {
                    "acceptance": "typed-plan",
                },
            },
            {
                "role": "Developer",
                "op": "execute_vxn",
                "header": {
                    "scope": "virtual-workspace",
                    "authority": "EDIT_STAGE",
                },
                "footer": {
                    "evidence": True,
                },
            },
            {
                "role": "Reviewer",
                "op": "verify",
                "header": {
                    "scope": "revision",
                    "authority": "VERIFY",
                },
                "footer": {
                    "acceptance": "evidence",
                },
            },
        ]

        return m

    def _coerce_signal(self, signal: Any) -> InputSignal:
        if isinstance(signal, InputSignal):
            return signal

        if isinstance(signal, str):
            return InputSignal(
                content=signal,
                source="HUMAN",
                modality="TEXT",
            )

        if isinstance(signal, dict):
            return InputSignal(
                content=signal.get("content"),
                source=str(
                    signal.get("source", "HUMAN")
                ),
                modality=str(
                    signal.get("modality", "TEXT")
                ),
                context=dict(
                    signal.get("context") or {}
                ),
                evidence=tuple(
                    signal.get("evidence") or ()
                ),
                confidence=float(
                    signal.get("confidence", 1.0)
                ),
                requested_capability=(
                    signal.get("requested_capability")
                ),
            )

        raise TypeError(
            "signal must be InputSignal, str or dict"
        )

    @staticmethod
    def _extract_intent(
        signal: InputSignal,
    ) -> str:
        content = signal.content

        if isinstance(content, str):
            return content.strip()

        if isinstance(content, dict):
            for key in (
                "intent",
                "text",
                "transcript",
                "recognized_text",
            ):
                value = content.get(key)

                if isinstance(value, str):
                    value = value.strip()

                    if value:
                        return value

        context_intent = signal.context.get("intent")

        if isinstance(context_intent, str):
            return context_intent.strip()

        return ""

    def normalize(
        self,
        signal: Any,
        world_context=None,
    ) -> SemanticEnvelope:
        """
        Convert adapter-specific ingress into the canonical envelope.
        """

        item = self._coerce_signal(signal)

        confidence = float(item.confidence)

        if confidence < 0.0:
            confidence = 0.0
        elif confidence > 1.0:
            confidence = 1.0

        context = dict(world_context or {})
        context.update(dict(item.context))

        return SemanticEnvelope(
            intent=self._extract_intent(item),
            source=item.source,
            modality=item.modality,
            context=context,
            evidence=tuple(item.evidence),
            confidence=confidence,
            requested_capability=(
                item.requested_capability
            ),
        )

    def _authorized_grants(self):
        """
        Only mothership-authorized grants are selectable.
        """

        return tuple(
            grant
            for grant in self._capability_grants
            if (
                isinstance(grant, CapabilityGrant)
                and grant.enabled
                and grant.authority_source
                == "MOTHERSHIP"
            )
        )

    def route(
        self,
        envelope: SemanticEnvelope,
    ) -> RoutingDecision:
        """
        Select an already-authorized execution capability.

        No grant creation or Brain Cartridge replacement occurs here.
        """

        grants = self._authorized_grants()
        requested = envelope.requested_capability

        if requested:
            for grant in grants:
                if grant.name == requested:
                    return RoutingDecision(
                        decision="PASS",
                        capability=grant.name,
                        kind=grant.kind,
                        reason="mothership grant",
                    )

            return RoutingDecision(
                decision="DENY",
                capability=requested,
                reason="capability not granted by mothership",
            )

        if not grants:
            return RoutingDecision(
                decision="DEFERRED",
                reason="no execution capability required or available",
            )

        grant = sorted(
            grants,
            key=lambda item: (
                item.priority,
                item.name,
            ),
        )[0]

        return RoutingDecision(
            decision="PASS",
            capability=grant.name,
            kind=grant.kind,
            reason="automatic selection from mothership grants",
        )

    def ingest(
        self,
        signal: Any,
        world_context=None,
    ) -> IngestResult:
        """
        Canonical HYPER ingress pipeline.

        signal
          -> normalize
          -> confidence / ambiguity gate
          -> capability routing
          -> Mission compile
        """

        envelope = self.normalize(
            signal,
            world_context,
        )

        if not envelope.intent:
            gate = HumanGateRequest(
                reason="intent_missing",
                message=(
                    "Input was captured but intent "
                    "could not be resolved."
                ),
                confidence=envelope.confidence,
                missing=("intent",),
            )

            return IngestResult(
                decision="HUMAN_GATE",
                envelope=envelope,
                human_gate=gate,
            )

        if (
            envelope.confidence
            < self._confidence_threshold
        ):
            gate = HumanGateRequest(
                reason="low_confidence",
                message=(
                    "Input confidence is below "
                    "the HYPER Agent threshold."
                ),
                confidence=envelope.confidence,
            )

            return IngestResult(
                decision="HUMAN_GATE",
                envelope=envelope,
                human_gate=gate,
            )

        route = self.route(envelope)

        if route.decision == "DENY":
            return IngestResult(
                decision="DENIED",
                envelope=envelope,
                route=route,
            )

        context = dict(envelope.context)

        context["_hyper"] = {
            "source": envelope.source,
            "modality": envelope.modality,
            "confidence": envelope.confidence,
            "evidence": list(envelope.evidence),
            "routing": {
                "decision": route.decision,
                "capability": route.capability,
                "kind": route.kind,
                "reason": route.reason,
            },
        }

        mission = self.compile(
            envelope.intent,
            context,
        )

        return IngestResult(
            decision="PASS",
            envelope=envelope,
            mission=mission,
            route=route,
        )
