import time
from pathlib import Path
from typing import Any, Dict
from .errors import ValidationError
from .bridges.ard import ARDRelationBridge

class HyperAgentRouter:
    def __init__(self, policy, audit, missions, vur, vve, repository, commands):
        self.policy=policy
        self.audit=audit
        self.missions=missions
        self.vur=vur
        self.vve=vve
        self.repository=repository
        self.commands=commands

    def _ard(self):
        graph=ARDRelationBridge()
        reg=self.vur.registry()
        graph.load_vur_registry(reg)
        graph.load_vve_changesets(self.vve.list_changesets())
        return graph

    def dispatch(self, mission: Dict[str, Any]) -> Dict[str, Any]:
        cap=mission["capability"]
        self.policy.require(cap)
        mission["state"]="RUNNING"
        self.missions.save(mission)
        self.audit.append({"event":"MISSION_START","mission_id":mission["mission_id"],"capability":cap,"actor":mission.get("actor")})

        payload=mission.get("payload") or {}

        if cap=="READ_VUR":
            result={"summary":self.vur.summary()}
        elif cap=="READ_VVE":
            result={"changesets":self.vve.list_changesets()}
        elif cap=="WRITE_VVE":
            result=self.vve.create_changeset(payload["project_id"], payload.get("changes",[]), "VCRAS")
        elif cap=="GIT_INSPECT":
            result=self.repository.inspect()
        elif cap=="READ_ARD_GRAPH":
            graph=self._ard()
            result={"edges":graph.edges}
        elif cap=="QUERY_RELATIONS":
            graph=self._ard()
            target=payload.get("asset_id")
            if not target: raise ValidationError("asset_id required")
            mode=payload.get("mode","neighbors")
            result=graph.impact(target, int(payload.get("max_depth",4))) if mode=="impact" else graph.neighbors(target)
        elif cap in ("BUILD","TEST"):
            profile=payload.get("profile")
            if not profile: raise ValidationError("profile required")
            result=self.commands.run(profile)
        elif cap=="MISSION_SUBMIT":
            result={"accepted":True,"mission_id":mission["mission_id"]}
        else:
            raise ValidationError("no handler for capability: %s" % cap)

        mission["state"]="COMPLETED"
        mission["completed_at"]=time.time()
        mission["result"]=result
        self.missions.save(mission)
        self.audit.append({"event":"MISSION_COMPLETE","mission_id":mission["mission_id"],"capability":cap,"actor":mission.get("actor")})
        return mission
