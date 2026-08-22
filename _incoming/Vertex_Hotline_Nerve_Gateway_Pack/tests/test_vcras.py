import unittest
from vertex_gateway.vcras import VCRASEnvelope

class TestVCRAS(unittest.TestCase):
    def test_envelope(self):
        m=VCRASEnvelope.normalize({"mission_type":"QUERY","capability":"READ_VUR","payload":{}})
        self.assertTrue(m["mission_id"].startswith("mission://"))
        self.assertEqual(m["channel"],"VCRAS")
