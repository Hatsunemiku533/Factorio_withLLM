"""Check Mira's MCP handshake and tool list without a model or game connection."""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    messages = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "check", "version": "0"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
    ]
    process = subprocess.run(
        [sys.executable, "-B", "adapter/mira_mcp.py"],
        cwd=ROOT,
        input="".join(json.dumps(message) + "\n" for message in messages),
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=15,
        check=True,
    )
    responses = [json.loads(line) for line in process.stdout.splitlines() if line.strip()]
    assert [response["id"] for response in responses] == [1, 2], responses
    assert responses[0]["result"]["serverInfo"]["name"] == "factorio-mira"
    tools = responses[1]["result"]["tools"]
    expected = {
        "observe", "move_to", "stop", "inventory", "scan_resources",
        "mine_resource", "inspect_recipe", "craft", "locate",
        "inspect_smelting_recipe", "inspect_item", "place_item",
        "rotate_entity", "dismantle_entity", "inspect_entity", "insert_into_entity",
        "take_from_entity", "wait_for_entity", "memory_read",
        "memory_update_current", "memory_append_log",
        "memory_propose_long_term", "board_read", "board_post", "episode_finish",
    }
    names = {tool["name"] for tool in tools}
    assert len(tools) == 25, names
    assert names == expected, names ^ expected
    assert all(tool["inputSchema"]["type"] == "object" for tool in tools)
    schemas = {tool["name"]: tool["inputSchema"] for tool in tools}
    place = schemas["place_item"]["properties"]["direction"]
    assert place == {"type": "string", "enum": ["north", "east", "south", "west"]}
    assert "direction" not in schemas["place_item"].get("required", [])
    rotate = schemas["rotate_entity"]
    assert rotate["required"] == ["unit_number", "direction"]
    episode = schemas["episode_finish"]
    assert episode["properties"]["status"]["enum"] == ["continue", "blocker"]
    assert set(episode["required"]) == {"status", "summary", "current_goal"}
    assert schemas["episode_finish"]["properties"]["status"]["type"] == "string"
    assert schemas["board_post"]["required"] == ["to", "text"]
    assert "author" not in schemas["board_post"]["properties"]
    print("PASS: MCP handshake and all 25 allowed tools; no game calls or model requests.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
