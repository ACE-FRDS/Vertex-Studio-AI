import unittest, tempfile
from pathlib import Path
from vertex_gateway.bridges.vve import VVEBridge

class TestVVE(unittest.TestCase):
    def test_create_is_non_destructive(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            v=VVEBridge(root,root/"outbox")
            cs=v.create_changeset("project://x", [{"path":"a.txt","operation":"CREATE"}])
            self.assertFalse(cs["real_repository_write"])
            self.assertTrue(cs["human_gate_required"])
