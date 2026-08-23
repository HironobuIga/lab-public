"""Minimal OAuth 2.0 authorization server for the client_credentials grant.

Local demo only: HS256 with a hard-coded shared secret, one static client,
no storage. Every request is logged so the token exchange is observable.

Run: uv run python auth_server.py  (listens on http://127.0.0.1:9001)
"""

import base64
import json
import logging
import time
import uuid

import jwt
import uvicorn
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route

logging.basicConfig(level=logging.INFO, format="[AS] %(message)s")
log = logging.getLogger(__name__)

ISSUER = "http://127.0.0.1:9001"
# Shared with mcp_server.py. Local demo only — a real deployment would use
# asymmetric keys and a JWKS endpoint instead of a shared secret.
JWT_SECRET = "local-demo-secret-not-for-production"
CLIENT_ID = "lab-client"
CLIENT_SECRET = "lab-client-secret"
TOKEN_TTL_SECONDS = 300
# Fallback audience when the client sends no RFC 8707 `resource` parameter.
DEFAULT_AUDIENCE = "http://127.0.0.1:9000/mcp"


async def metadata(request: Request) -> JSONResponse:
    """RFC 8414 authorization server metadata.

    `authorization_endpoint` is required by the MCP client's metadata model even
    though the client_credentials grant never uses it, so a dummy URL is served.
    """
    log.info("GET %s", request.url.path)
    return JSONResponse(
        {
            "issuer": ISSUER,
            "authorization_endpoint": f"{ISSUER}/authorize",
            "token_endpoint": f"{ISSUER}/token",
            "grant_types_supported": ["client_credentials"],
            "response_types_supported": ["none"],
            "token_endpoint_auth_methods_supported": ["client_secret_basic", "client_secret_post"],
        }
    )


async def authorize(request: Request) -> JSONResponse:
    return JSONResponse({"error": "unsupported_response_type"}, status_code=400)


def _authenticate_client(request: Request, form: dict[str, str]) -> tuple[str, str] | None:
    """Return (client_id, auth_method) if the client authenticated, else None."""
    header = request.headers.get("authorization", "")
    if header.startswith("Basic "):
        decoded = base64.b64decode(header.removeprefix("Basic ")).decode()
        client_id, _, client_secret = decoded.partition(":")
        if client_id == CLIENT_ID and client_secret == CLIENT_SECRET:
            return client_id, "client_secret_basic"
        return None
    if form.get("client_id") == CLIENT_ID and form.get("client_secret") == CLIENT_SECRET:
        return CLIENT_ID, "client_secret_post"
    return None


async def token(request: Request) -> JSONResponse:
    form = {key: value for key, value in (await request.form()).items() if isinstance(value, str)}
    grant_type = form.get("grant_type")
    scope = form.get("scope")
    resource = form.get("resource")

    authenticated = _authenticate_client(request, form)
    log.info(
        "POST /token grant_type=%s auth=%s scope=%r resource=%r",
        grant_type,
        authenticated[1] if authenticated else "FAILED",
        scope,
        resource,
    )
    if authenticated is None:
        return JSONResponse({"error": "invalid_client"}, status_code=401)
    if grant_type != "client_credentials":
        return JSONResponse({"error": "unsupported_grant_type"}, status_code=400)

    client_id, _ = authenticated
    now = int(time.time())
    granted_scope = scope or ""
    claims = {
        "iss": ISSUER,
        "sub": client_id,
        "aud": resource or DEFAULT_AUDIENCE,
        "scope": granted_scope,
        "iat": now,
        "exp": now + TOKEN_TTL_SECONDS,
        "jti": str(uuid.uuid4()),
    }
    access_token = jwt.encode(claims, JWT_SECRET, algorithm="HS256")
    log.info("issued token: %s", json.dumps({k: claims[k] for k in ("sub", "aud", "scope", "exp")}))
    return JSONResponse(
        {
            "access_token": access_token,
            "token_type": "Bearer",
            "expires_in": TOKEN_TTL_SECONDS,
            "scope": granted_scope,
        }
    )


app = Starlette(
    routes=[
        Route("/.well-known/oauth-authorization-server", metadata),
        Route("/authorize", authorize),
        Route("/token", token, methods=["POST"]),
    ]
)

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=9001, log_level="warning")
