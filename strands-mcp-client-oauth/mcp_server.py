"""MCP resource server (streamable HTTP) protected by JWT bearer tokens.

Built on the official MCP Python SDK: `AuthSettings(resource_server_url=...)`
makes FastMCP serve RFC 9728 protected resource metadata and answer
unauthenticated requests with 401 + `WWW-Authenticate: Bearer resource_metadata=...`.
The metadata advertises `required_scopes` as `scopes_supported` and this server's
issuer as the authorization server — that is everything the client discovers.

Run: uv run python mcp_server.py                    (advertises scope "mcp:tools")
     RS_ADVERTISE_SCOPES=0 uv run python mcp_server.py   (advertises no scopes)
     RS_REQUIRED_SCOPES="mcp:tools mcp:admin" uv run python mcp_server.py
                                                    (requires and advertises both)
Listens on http://127.0.0.1:9000/mcp
"""

import logging
import os

import jwt
from mcp.server.auth.middleware.auth_context import get_access_token
from mcp.server.auth.provider import AccessToken
from mcp.server.auth.settings import AuthSettings
from mcp.server.fastmcp import FastMCP
from pydantic import AnyHttpUrl

logging.basicConfig(level=logging.INFO, format="[RS] %(message)s")
log = logging.getLogger(__name__)

ISSUER = "http://127.0.0.1:9001"
RESOURCE = "http://127.0.0.1:9000/mcp"
JWT_SECRET = "local-demo-secret-not-for-production"  # shared with auth_server.py
ADVERTISE_SCOPES = os.environ.get("RS_ADVERTISE_SCOPES", "1") != "0"
# Scopes the RS requires, and therefore advertises as `scopes_supported`.
REQUIRED_SCOPES = os.environ.get("RS_REQUIRED_SCOPES", "mcp:tools").split() if ADVERTISE_SCOPES else None


class JWTVerifier:
    """Validate HS256 JWTs issued by the local authorization server."""

    async def verify_token(self, token: str) -> AccessToken | None:
        try:
            claims = jwt.decode(
                token,
                JWT_SECRET,
                algorithms=["HS256"],
                issuer=ISSUER,
                # The AS sets `aud` from the RFC 8707 `resource` parameter.
                audience=RESOURCE,
            )
        except jwt.InvalidTokenError as error:
            log.info("token rejected: %s", error)
            return None
        log.info("token accepted: sub=%s scope=%r aud=%s", claims["sub"], claims["scope"], claims["aud"])
        return AccessToken(
            token=token,
            client_id=claims["sub"],
            scopes=claims["scope"].split() if claims["scope"] else [],
            expires_at=claims["exp"],
        )


mcp = FastMCP(
    name="lab-protected-server",
    host="127.0.0.1",
    port=9000,
    token_verifier=JWTVerifier(),
    auth=AuthSettings(
        issuer_url=AnyHttpUrl(ISSUER),
        resource_server_url=AnyHttpUrl(RESOURCE),
        required_scopes=REQUIRED_SCOPES,
    ),
)


@mcp.tool()
def whoami() -> dict:
    """Return the resource server's view of the caller's access token."""
    access_token = get_access_token()
    assert access_token is not None
    return {"client_id": access_token.client_id, "scopes": access_token.scopes}


@mcp.tool()
def add(a: int, b: int) -> int:
    """Add two integers."""
    return a + b


if __name__ == "__main__":
    log.info("advertised scopes: %s", REQUIRED_SCOPES)
    mcp.run(transport="streamable-http")
