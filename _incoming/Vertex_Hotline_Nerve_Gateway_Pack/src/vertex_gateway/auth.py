import hmac, os
from .errors import AuthError

class OwnerAuth:
    def __init__(self, require_token: bool, token_env: str):
        self.require_token = require_token
        self.token_env = token_env

    def verify(self, presented: str) -> str:
        if not self.require_token:
            return "owner"
        expected = os.environ.get(self.token_env, "")
        if not expected:
            raise AuthError("owner token is not configured")
        if not presented or not hmac.compare_digest(expected, presented):
            raise AuthError("invalid owner token")
        return "owner"
