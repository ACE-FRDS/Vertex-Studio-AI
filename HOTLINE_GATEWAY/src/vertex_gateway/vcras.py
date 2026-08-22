import uuid, time
from typing import Any, Dict
from .errors import ValidationError

class VCRASEnvelope:
    REQUIRED = ("mission_type", "capability", "payload")

    @classmethod
    def normalize(cls, doc: Dict[str, Any]) -> Dict[str, Any]:
        for key in cls.REQUIRED:
            if key not in doc:
                raise ValidationError("missing field: %s" % key)
        out = dict(doc)
        out.setdefault("mission_id", "mission://%s" % uuid.uuid4())
        out.setdefault("actor", "owner")
        out.setdefault("created_at", time.time())
        out.setdefault("channel", "VCRAS")
        return out
