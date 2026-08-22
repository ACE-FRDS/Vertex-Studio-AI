class GatewayError(Exception): pass
class AuthError(GatewayError): pass
class CapabilityDenied(GatewayError): pass
class ValidationError(GatewayError): pass
class MissionError(GatewayError): pass
