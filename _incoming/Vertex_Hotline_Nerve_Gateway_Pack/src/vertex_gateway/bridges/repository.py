import subprocess
from pathlib import Path
from typing import Any, Dict

class RepositoryBridge:
    def __init__(self, root: Path):
        self.root = root

    def _git(self, *args: str) -> Dict[str, Any]:
        p = subprocess.run(
            ["git","-C",str(self.root)] + list(args),
            capture_output=True, text=True, timeout=30
        )
        return {"returncode":p.returncode,"stdout":p.stdout.strip(),"stderr":p.stderr.strip()}

    def inspect(self) -> Dict[str, Any]:
        return {
            "root": str(self.root),
            "branch": self._git("branch","--show-current"),
            "commit": self._git("rev-parse","HEAD"),
            "status": self._git("status","--porcelain"),
            "is_worktree": self._git("rev-parse","--is-inside-work-tree")
        }

    def diff_stat(self) -> Dict[str, Any]:
        return self._git("diff","--stat")
