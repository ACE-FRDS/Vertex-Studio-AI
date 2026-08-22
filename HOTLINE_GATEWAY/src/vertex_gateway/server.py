import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from .config import GatewayConfig
from .audit import AuditLog
from .auth import OwnerAuth
from .policy import CapabilityPolicy
from .missions import MissionStore
from .vcras import VCRASEnvelope
from .router import HyperAgentRouter
from .commands import CommandProfiles
from .repository_map import RepositoryMap
from .bridges.vur import VURBridge
from .bridges.vve import VVEBridge
from .bridges.repository import RepositoryBridge
from .errors import GatewayError


class Runtime:
    def __init__(self, root: Path):
        self.root = root
        cfg = GatewayConfig(root)
        self.cfg = cfg

        g = cfg.gateway

        self.auth = OwnerAuth(
            bool(g.get("require_token", True)),
            g.get(
                "token_env",
                "VERTEX_VCRAS_TOKEN"
            )
        )

        self.policy = CapabilityPolicy(
            cfg.capabilities
        )

        self.audit = AuditLog(
            root / g.get(
                "audit_file",
                "STATE/audit.jsonl"
            )
        )

        self.missions = MissionStore(
            root / g.get(
                "mission_store",
                "STATE/missions"
            )
        )

        self.vur = VURBridge(
            Path(g["vur_root"])
        )

        self.vve = VVEBridge(
            Path(g["vve_root"]),
            Path(g["vve_outbox"])
        )

        self.repository = RepositoryBridge(
            Path(g["repository_root"])
        )

        self.repository_map = RepositoryMap(
            root / "CONFIG" / "repositories.json"
        )

        self.commands = CommandProfiles(
            cfg.command_profiles
        )

        self.router = HyperAgentRouter(
            self.policy,
            self.audit,
            self.missions,
            self.vur,
            self.vve,
            self.repository,
            self.repository_map,
            self.commands
        )


class Handler(BaseHTTPRequestHandler):
    runtime = None
    server_version = "VertexGateway/0.2"

    def _send(self, code, obj):
        data = json.dumps(
            obj,
            ensure_ascii=False,
            indent=2
        ).encode("utf-8")

        self.send_response(code)
        self.send_header(
            "Content-Type",
            "application/json; charset=utf-8"
        )
        self.send_header(
            "Content-Length",
            str(len(data))
        )
        self.end_headers()
        self.wfile.write(data)

    def _auth(self):
        token = self.headers.get(
            "X-Vertex-Owner-Token",
            ""
        )
        return self.runtime.auth.verify(token)

    def do_GET(self):
        try:
            if self.path == "/health":
                self._send(
                    200,
                    {
                        "ok": True,
                        "service": "VCRAS/VCG",
                        "version": "0.2.0"
                    }
                )
                return

            self._auth()

            if self.path == "/capabilities":
                self._send(
                    200,
                    {
                        "enabled":
                        self.runtime.policy.list_enabled()
                    }
                )
                return

            if self.path == "/vur/status":
                self.runtime.policy.require(
                    "READ_VUR"
                )
                self._send(
                    200,
                    self.runtime.vur.summary()
                )
                return

            self._send(
                404,
                {"error": "not found"}
            )

        except GatewayError as e:
            self._send(
                403,
                {"error": str(e)}
            )

        except Exception as e:
            self._send(
                500,
                {"error": str(e)}
            )

    def do_POST(self):
        try:
            self._auth()

            length = int(
                self.headers.get(
                    "Content-Length",
                    "0"
                )
            )

            raw = self.rfile.read(length)

            doc = json.loads(
                raw.decode("utf-8")
            )

            if self.path == "/mission":
                mission = VCRASEnvelope.normalize(
                    doc
                )

                result = (
                    self.runtime.router.dispatch(
                        mission
                    )
                )

                self._send(
                    200,
                    result
                )
                return

            self._send(
                404,
                {"error": "not found"}
            )

        except GatewayError as e:
            self._send(
                403,
                {"error": str(e)}
            )

        except Exception as e:
            self._send(
                500,
                {"error": str(e)}
            )

    def log_message(self, fmt, *args):
        pass


def serve(root: Path):
    runtime = Runtime(root)

    Handler.runtime = runtime

    server = ThreadingHTTPServer(
        (
            runtime.cfg.bind_host,
            runtime.cfg.bind_port
        ),
        Handler
    )

    print(
        "Vertex Hotline Nerve Gateway"
    )
    print(
        "Listening on http://%s:%s"
        % (
            runtime.cfg.bind_host,
            runtime.cfg.bind_port
        )
    )

    server.serve_forever()