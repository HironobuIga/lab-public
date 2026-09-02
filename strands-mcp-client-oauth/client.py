"""Strands MCPClient scenarios against the OAuth-protected MCP server.

Each scenario prints the httpx request log, so the discovery sequence
(401 -> protected resource metadata -> AS metadata -> token -> retry) is visible
from the client side; auth_server.py and mcp_server.py log the server side.

Run: uv run python client.py <happy|reuse|wrong-secret|client-scopes|client-subset>
"""

import logging
import sys

from strands.tools.mcp import MCPClient
from strands.tools.mcp.mcp_types import MCPClientCredentials

MCP_URL = "http://127.0.0.1:9000/mcp"

logging.basicConfig(level=logging.WARNING, format="[client] %(name)s: %(message)s")
# httpx logs one line per request with method, URL, and status code.
logging.getLogger("httpx").setLevel(logging.INFO)


def credentials(client_secret: str = "lab-client-secret", scopes: list[str] | None = None) -> MCPClientCredentials:
    auth = MCPClientCredentials(client_id="lab-client", client_secret=client_secret)
    if scopes is not None:
        auth["scopes"] = scopes
    return auth


def scenario_happy() -> None:
    """Discovery + token + tool call, starting from nothing but URL and credentials."""
    client = MCPClient(url=MCP_URL, auth=credentials())
    with client:
        tools = client.list_tools_sync()
        print("tools:", sorted(tool.tool_name for tool in tools))
        result = client.call_tool_sync(tool_use_id="whoami-1", name="whoami")
        print("whoami:", result["content"][0]["text"])


def scenario_reuse() -> None:
    """How many token requests do repeated calls and sessions cost?"""
    client = MCPClient(url=MCP_URL, auth=credentials())
    with client:
        client.call_tool_sync(tool_use_id="add-1", name="add", arguments={"a": 1, "b": 2})
        client.call_tool_sync(tool_use_id="add-2", name="add", arguments={"a": 3, "b": 4})
    print("--- second session on the same MCPClient instance ---")
    with client:
        client.call_tool_sync(tool_use_id="add-3", name="add", arguments={"a": 5, "b": 6})
    print("count POST /token lines in the AS log to see token reuse")


def scenario_wrong_secret() -> None:
    """What surfaces on the strands side when the AS rejects the client?"""
    client = MCPClient(url=MCP_URL, auth=credentials(client_secret="wrong"))
    try:
        with client:
            client.list_tools_sync()
    except Exception as error:  # noqa: BLE001 — the point is to show what type arrives
        print(f"raised {type(error).__name__}: {error}")


def scenario_client_scopes() -> None:
    """Pass scopes= from the client and see whether they reach the token request."""
    client = MCPClient(url=MCP_URL, auth=credentials(scopes=["mcp:read", "mcp:admin"]))
    with client:
        client.list_tools_sync()
    print("check the AS log: which scope did the token request actually carry?")


def scenario_client_subset() -> None:
    """Ask for a subset of what the RS advertises. Does the narrower choice reach the token request?

    Run the RS with RS_REQUIRED_SCOPES="mcp:tools mcp:admin" so it advertises both.
    """
    client = MCPClient(url=MCP_URL, auth=credentials(scopes=["mcp:tools"]))
    with client:
        result = client.call_tool_sync(tool_use_id="whoami-subset", name="whoami")
        print("whoami:", result["content"][0]["text"])
    print("check the AS log: which scope did the token request actually carry?")


SCENARIOS = {
    "happy": scenario_happy,
    "reuse": scenario_reuse,
    "wrong-secret": scenario_wrong_secret,
    "client-scopes": scenario_client_scopes,
    "client-subset": scenario_client_subset,
}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in SCENARIOS:
        print(f"usage: python client.py <{'|'.join(SCENARIOS)}>")
        sys.exit(1)
    SCENARIOS[sys.argv[1]]()
