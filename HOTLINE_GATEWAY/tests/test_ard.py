import unittest
from vertex_gateway.bridges.ard import ARDRelationBridge

class TestARD(unittest.TestCase):
    def test_graph(self):
        g=ARDRelationBridge()
        g.add("DEPENDS_ON","a","b")
        g.add("COMPOSED_OF","b","c")
        out=g.impact("a",3)
        self.assertIn("c",out["nodes"])
