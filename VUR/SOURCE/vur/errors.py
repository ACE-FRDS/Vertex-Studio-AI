class VURError(Exception): pass
class PolicyDenied(VURError): pass
class RegistryError(VURError): pass
class IntegrityError(VURError): pass
class PromotionDenied(VURError): pass
