from pathlib import Path
from typing import Any, Dict, List
import subprocess

from .util import read_json


class RepositoryMap:
    def __init__(self, config_path: Path):
        self.config_path = config_path
        self.document = read_json(config_path)

    def repositories(self) -> List[Dict[str, Any]]:
        return list(self.document.get("repositories", []))

    def get(self, repository_id: str) -> Dict[str, Any]:
        for repo in self.repositories():
            if repo.get("repository_id") == repository_id:
                return repo
        raise KeyError("repository not registered: %s" % repository_id)

    def inspect(self, repository_id: str) -> Dict[str, Any]:
        repo = self.get(repository_id)
        root = Path(repo["path"])

        result = dict(repo)
        result["exists"] = root.exists()

        if not root.exists():
            result["git"] = {
                "ok": False,
                "error": "repository path does not exist"
            }
            return result

        def git(*args: str) -> Dict[str, Any]:
            p = subprocess.run(
                ["git", "-C", str(root)] + list(args),
                capture_output=True,
                text=True,
                timeout=30
            )
            return {
                "returncode": p.returncode,
                "stdout": p.stdout.strip(),
                "stderr": p.stderr.strip()
            }

        result["git"] = {
            "toplevel": git("rev-parse", "--show-toplevel"),
            "branch": git("branch", "--show-current"),
            "commit": git("rev-parse", "--short", "HEAD"),
            "remote": git("remote", "get-url", "origin"),
            "status": git("status", "--porcelain")
        }

        return result

    def inspect_all(self) -> List[Dict[str, Any]]:
        return [
            self.inspect(repo["repository_id"])
            for repo in self.repositories()
        ]

    def relation_edges(self) -> List[Dict[str, Any]]:
        edges = []

        mothership = self.document.get("mothership", {})
        mothership_id = mothership.get(
            "project_id",
            "project://vertex-studio/mothership"
        )

        for repo in self.repositories():
            repo_id = repo["repository_id"]
            project_id = repo.get("project_id")

            if project_id:
                edges.append({
                    "relation_type": "HAS_REPOSITORY",
                    "source_id": project_id,
                    "target_id": repo_id,
                    "metadata": {
                        "source": "REPOSITORY_MAP",
                        "role": repo.get("role")
                    }
                })

            if repo.get("role") == "REAL_REPOSITORY":
                edges.append({
                    "relation_type": "REALIZED_BY",
                    "source_id": mothership_id,
                    "target_id": repo_id,
                    "metadata": {
                        "source": "REPOSITORY_MAP"
                    }
                })

        return edges