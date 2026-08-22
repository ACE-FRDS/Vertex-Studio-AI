import time
from typing import Any, Dict

from .errors import ValidationError
from .bridges.ard import ARDRelationBridge


class HyperAgentRouter:
    def __init__(
        self,
        policy,
        audit,
        missions,
        vur,
        vve,
        repository,
        repository_map,
        commands
    ):
        self.policy = policy
        self.audit = audit
        self.missions = missions
        self.vur = vur
        self.vve = vve
        self.repository = repository
        self.repository_map = repository_map
        self.commands = commands

    def _ard(self):
        graph = ARDRelationBridge()

        graph.load_vur_registry(
            self.vur.registry()
        )

        graph.load_vve_changesets(
            self.vve.list_changesets()
        )

        graph.load_repository_edges(
            self.repository_map.relation_edges()
        )

        return graph

    def dispatch(self, mission: Dict[str, Any]) -> Dict[str, Any]:
        capability = mission["capability"]

        self.policy.require(capability)

        mission["state"] = "RUNNING"
        self.missions.save(mission)

        self.audit.append({
            "event": "MISSION_START",
            "mission_id": mission["mission_id"],
            "capability": capability,
            "actor": mission.get("actor")
        })

        payload = mission.get("payload") or {}

        if capability == "READ_VUR":
            result = {
                "summary": self.vur.summary()
            }

        elif capability == "READ_VVE":
            result = {
                "changesets": self.vve.list_changesets()
            }

        elif capability == "READ_MOTHERSHIP_STATE":
            import json
            from pathlib import Path

            state_path = Path(
                r"G:\Vertex Protocol\Vertex Project\OBSERVATORY\CURRENT\MOTHERSHIP_STATE.json"
            )

            if not state_path.exists():
                raise ValidationError(
                    "mothership state not found"
                )

            result = json.loads(
                state_path.read_text(
                    encoding="utf-8-sig"
                )
            )

        elif capability == "READ_MOTHERSHIP_DELTA":
            import json
            from pathlib import Path

            delta_path = Path(
                r"G:\Vertex Protocol\Vertex Project\OBSERVATORY\CURRENT\MOTHERSHIP_DELTA.json"
            )

            if not delta_path.exists():
                raise ValidationError(
                    "mothership delta not found"
                )

            result = json.loads(
                delta_path.read_text(
                    encoding="utf-8-sig"
                )
            )

        elif capability == "WRITE_VVE":
            result = self.vve.create_changeset(
                payload["project_id"],
                payload.get("changes", []),
                "VCRAS"
            )

        elif capability == "GIT_INSPECT":
            repository_id = payload.get("repository_id")

            if repository_id:
                result = self.repository_map.inspect(
                    repository_id
                )
            else:
                result = {
                    "repositories":
                    self.repository_map.inspect_all()
                }

        elif capability == "READ_ARD_GRAPH":
            graph = self._ard()

            result = {
                "edges": graph.edges
            }

        elif capability == "QUERY_RELATIONS":
            graph = self._ard()
            target = payload.get("asset_id")

            if not target:
                raise ValidationError(
                    "asset_id required"
                )

            mode = payload.get(
                "mode",
                "neighbors"
            )

            if mode == "impact":
                result = graph.impact(
                    target,
                    int(payload.get("max_depth", 4))
                )
            else:
                result = graph.neighbors(target)

        elif capability in ("BUILD", "TEST"):
            profile = payload.get("profile")

            if not profile:
                raise ValidationError(
                    "profile required"
                )

            result = self.commands.run(
                profile
            )

        elif capability == "MISSION_SUBMIT":
            result = {
                "accepted": True,
                "mission_id": mission["mission_id"]
            }

        else:
            raise ValidationError(
                "no handler for capability: %s"
                % capability
            )

        mission["state"] = "COMPLETED"
        mission["completed_at"] = time.time()
        mission["result"] = result

        self.missions.save(mission)

        self.audit.append({
            "event": "MISSION_COMPLETE",
            "mission_id": mission["mission_id"],
            "capability": capability,
            "actor": mission.get("actor")
        })

        return mission