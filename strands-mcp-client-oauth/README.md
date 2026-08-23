# Strands MCPClient OAuth (client_credentials) against a local AS + RS

Verifies what Strands Agents v1.53.0's built-in `MCPClient(auth=...)` does on the wire:
discovery chain, scope selection, token reuse, and failure modes — all running locally.

## Related article

- ja: https://portfolio-site.iganin.workers.dev/ja/articles/strands-mcp-client-oauth/
- en: https://portfolio-site.iganin.workers.dev/en/articles/strands-mcp-client-oauth/

## Environment

| What             | Version |
| ---------------- | ------- |
| Python           | 3.12    |
| strands-agents   | 1.53.0  |
| mcp (transitive) | 1.29.0  |
| uv               | 0.9.5   |

## Layout

- `auth_server.py` — minimal OAuth 2.0 authorization server (client_credentials only,
  HS256, one static client, RFC 8414 metadata). Port 9001. Local demo only.
- `mcp_server.py` — MCP resource server on the official SDK (`FastMCP` + `TokenVerifier`
  + `AuthSettings`), streamable HTTP. Serves RFC 9728 protected resource metadata.
  Port 9000, path `/mcp`. `RS_ADVERTISE_SCOPES=0` drops `scopes_supported`.
- `client.py` — Strands `MCPClient` scenarios: `happy`, `reuse`, `wrong-secret`,
  `client-scopes`.

## How to run

```sh
uv sync
uv run python auth_server.py   # terminal 1
uv run python mcp_server.py    # terminal 2
uv run python client.py happy  # terminal 3
```

The client-side httpx log shows the discovery sequence
(401 → protected resource metadata → AS metadata → token → retry);
the AS log shows which `scope` and `resource` each token request carried.
