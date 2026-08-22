import os, subprocess
from typing import Any, Dict
from .errors import ValidationError

class CommandProfiles:
    def __init__(self, document: Dict[str, Any]):
        self.profiles = document.get("profiles", {})

    def run(self, profile_name: str) -> Dict[str, Any]:
        profile = self.profiles.get(profile_name)
        if not profile:
            raise ValidationError("unknown command profile: %s" % profile_name)
        argv = profile.get("argv")
        if not isinstance(argv, list) or not argv:
            raise ValidationError("invalid profile argv")
        env = os.environ.copy()
        env.update(profile.get("env", {}))
        p = subprocess.run(
            argv,
            cwd=profile.get("cwd") or None,
            env=env,
            capture_output=True,
            text=True,
            timeout=int(profile.get("timeout_sec", 60))
        )
        return {
            "profile":profile_name,
            "returncode":p.returncode,
            "stdout":p.stdout,
            "stderr":p.stderr
        }
