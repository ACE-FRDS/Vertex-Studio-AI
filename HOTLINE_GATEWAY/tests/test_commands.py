import unittest
from vertex_gateway.commands import CommandProfiles
from vertex_gateway.errors import ValidationError

class TestCommands(unittest.TestCase):
    def test_unknown_profile(self):
        c=CommandProfiles({"profiles":{}})
        with self.assertRaises(ValidationError):
            c.run("nope")
