import unittest
from vertex_gateway.policy import CapabilityPolicy
from vertex_gateway.errors import CapabilityDenied

class TestPolicy(unittest.TestCase):
    def test_allow_and_deny(self):
        p=CapabilityPolicy({"capabilities":{"READ_VUR":{"enabled":True},"ARBITRARY_SHELL":{"enabled":False}}})
        self.assertEqual(p.require("READ_VUR")["enabled"], True)
        with self.assertRaises(CapabilityDenied):
            p.require("ARBITRARY_SHELL")
