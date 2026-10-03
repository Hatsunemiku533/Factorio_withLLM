"""Restricted local MCP bridge for the Mira agent.

The model can observe, walk, stop, and update bounded memory files. Raw RCON,
item creation, resets, and arbitrary file paths are not exposed.
"""

import json
import sys
import time
from datetime import datetime
from pathlib import Path

import bridge_probe

ROOT = Path(__file__).resolve().parents[1]
MEMORY = ROOT / "memory"
LOG_DIR = MEMORY / "log"
PROTOCOL_VERSION = "2024-11-05"


def text_result(payload, is_error=False):
    return {
        "content": [{"type": "text", "text": json.dumps(payload, ensure_ascii=False, indent=2)}],
        "isError": is_error,
    }


def bounded_text(value, limit, name):
    if not isinstance(value, str):
        raise ValueError(f"{name} must be text")
    cleaned = value.replace("\r\n", "\n").strip()
    if not cleaned:
        raise ValueError(f"{name} is empty")
    if len(cleaned) > limit:
        raise ValueError(f"{name} exceeds {limit} characters")
    return cleaned + "\n"


def read_bounded(path, limit):
    if not path.exists():
        return ""
    text = path.read_text(encoding="utf-8")
    return text[:limit]


def observe():
    summary = bridge_probe.query()
    agent = bridge_probe.call_remote("agent_status")
    movement = bridge_probe.call_remote("movement_status")
    entities = []
    for entity in summary["entities"]:
        if entity["name"] in ("stone-furnace", "character", "crash-site-spaceship"):
            entities.append(entity)
    return {
        "surface": summary["surface"],
        "speed": summary["speed"],
        "tick": summary["tick"],
        "agent": agent,
        "movement": movement,
        "inventory": bridge_probe.call_remote("inventory"),
        "resources": bridge_probe.call_remote("scan_resources", {"radius": 96})["resources"],
        "action": bridge_probe.call_remote("action_status"),
        "entities": entities,
        "players": summary["players"],
        "characters": summary["characters"],
        "path_note": "no path may mean either blocked terrain or an ungenerated destination chunk",
    }


def lua_result(function_name, request):
    client = bridge_probe.connect()
    try:
        bridge_probe.send_lua(client, 'rcon.print("ready")')
        payload = "{x = " + format(float(request["x"]), ".6f") + ", y = " + format(float(request["y"]), ".6f") + "}"
        lua = (
            "local ok, result = pcall(remote.call, "
            f'"save_safe_bridge", "{function_name}", {payload}); '
            "if ok then rcon.print(helpers.table_to_json(result)) else rcon.print(result) end"
        )
        response = bridge_probe.send_lua(client, lua)
    finally:
        client.close()
    if response.startswith("Error"):
        raise RuntimeError(response.splitlines()[0])
    return json.loads(response)


def move_to(arguments):
    x = float(arguments["x"])
    y = float(arguments["y"])
    if abs(x) > 128 or abs(y) > 128:
        raise ValueError("target is outside the phase 3A nearby area")
    start = bridge_probe.call_remote("agent_status")
    lua_result("walk_to", {"x": x, "y": y})
    started = time.time()
    deadline = started + 35
    final = None
    while time.time() < deadline:
        final = bridge_probe.call_remote("movement_status")
        if final["state"] in ("arrived", "failed", "idle"):
            break
        time.sleep(0.75)
    else:
        bridge_probe.call_remote("stop_agent")
        final = bridge_probe.call_remote("movement_status")
        final["state"] = "failed"
        final["reason"] = "timeout"
    return {
        "requested": {"x": x, "y": y},
        "start": {"x": start["x"], "y": start["y"], "unit_number": start["unit_number"]},
        "final": final,
        "elapsed_seconds": round(time.time() - started, 2),
    }


def stop():
    return bridge_probe.call_remote("stop_agent")


def inventory():
    return bridge_probe.call_remote("inventory")


def scan_resources(arguments):
    radius = min(96, max(1, float(arguments.get("radius", 96))))
    return bridge_probe.call_remote("scan_resources", {"radius": radius})


def mine_resource(arguments):
    count = int(arguments["count"])
    if count < 1 or count > 10:
        raise ValueError("count must be between 1 and 10")
    return bridge_probe.call_remote("mine_resource", {
        "resource": str(arguments["resource"]),
        "x": float(arguments["x"]),
        "y": float(arguments["y"]),
        "count": count,
    })


def inspect_recipe(arguments):
    return bridge_probe.call_remote("inspect_recipe", {"item": str(arguments["item"])})


def craft(arguments):
    count = int(arguments["count"])
    if count < 1 or count > 5:
        raise ValueError("count must be between 1 and 5")
    started = bridge_probe.call_remote("craft_item", {"item": str(arguments["item"]), "count": count})
    recipe = bridge_probe.call_remote("inspect_recipe", {"item": str(arguments["item"])})
    time.sleep(max(0.5, float(recipe["energy"]) + 0.3))
    return {"started": started, "inventory": bridge_probe.call_remote("inventory")}


def update_current(arguments):
    path = MEMORY / "current.md"
    path.write_text(bounded_text(arguments["content"], 5000, "current memory"), encoding="utf-8")
    return {"rewritten": "memory/current.md", "bytes": path.stat().st_size}


def append_log(arguments):
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    entry = bounded_text(arguments["entry"], 2000, "log entry")
    path = LOG_DIR / (datetime.now().strftime("%Y-%m-%d") + ".md")
    with path.open("a", encoding="utf-8") as handle:
        handle.write(f"\n## {datetime.now().isoformat(timespec='seconds')}\n\n{entry}")
    return {"appended": f"memory/log/{path.name}", "bytes": path.stat().st_size}


def propose_long_term(arguments):
    proposal = bounded_text(arguments["proposal"], 1500, "proposal")
    path = MEMORY / "long_term_proposals.md"
    with path.open("a", encoding="utf-8") as handle:
        handle.write(f"\n## {datetime.now().isoformat(timespec='seconds')}\n\n{proposal}")
    return {"stored_proposal": "memory/long_term_proposals.md", "merged": False}


TOOLS = {
    "observe": {
        "description": "Read a compact live view of the test world. Live data overrides memory.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "handler": lambda arguments: observe(),
    },
    "move_to": {
        "description": "Walk Mira to nearby coordinates and wait until arrived, failed, or timeout.",
        "inputSchema": {
            "type": "object",
            "properties": {"x": {"type": "number"}, "y": {"type": "number"}},
            "required": ["x", "y"],
            "additionalProperties": False,
        },
        "handler": move_to,
    },
    "stop": {
        "description": "Stop Mira's current walking action.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "handler": lambda arguments: stop(),
    },
    "inventory": {
        "description": "Read Mira's own inventory. It cannot read the human inventory.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "handler": lambda arguments: inventory(),
    },
    "scan_resources": {
        "description": "Scan already generated resources near Mira, up to 96 tiles.",
        "inputSchema": {"type": "object", "properties": {"radius": {"type": "number"}}, "additionalProperties": False},
        "handler": scan_resources,
    },
    "mine_resource": {
        "description": "Mine one nearby resource for up to 10 products. Mira must already be within reach.",
        "inputSchema": {
            "type": "object",
            "properties": {"resource": {"type": "string"}, "x": {"type": "number"}, "y": {"type": "number"}, "count": {"type": "integer"}},
            "required": ["resource", "x", "y", "count"],
            "additionalProperties": False,
        },
        "handler": mine_resource,
    },
    "inspect_recipe": {
        "description": "Read one enabled crafting recipe, including ingredients, products, and time.",
        "inputSchema": {"type": "object", "properties": {"item": {"type": "string"}}, "required": ["item"], "additionalProperties": False},
        "handler": inspect_recipe,
    },
    "craft": {
        "description": "Craft 1 to 5 items from Mira's own inventory using the real recipe.",
        "inputSchema": {"type": "object", "properties": {"item": {"type": "string"}, "count": {"type": "integer"}}, "required": ["item", "count"], "additionalProperties": False},
        "handler": craft,
    },
    "memory_read": {
        "description": "Read the bounded long-term and current memory. Cold logs are excluded.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "handler": lambda arguments: {
            "long_term": read_bounded(MEMORY / "long_term.md", 12000),
            "current": read_bounded(MEMORY / "current.md", 6000),
        },
    },
    "memory_update_current": {
        "description": "Rewrite memory/current.md. This cannot target any other path.",
        "inputSchema": {
            "type": "object",
            "properties": {"content": {"type": "string"}},
            "required": ["content"],
            "additionalProperties": False,
        },
        "handler": update_current,
    },
    "memory_append_log": {
        "description": "Append one factual entry to today's cold log. Logs are not injected next time.",
        "inputSchema": {
            "type": "object",
            "properties": {"entry": {"type": "string"}},
            "required": ["entry"],
            "additionalProperties": False,
        },
        "handler": append_log,
    },
    "memory_propose_long_term": {
        "description": "Store a small long-term memory proposal without merging it automatically.",
        "inputSchema": {
            "type": "object",
            "properties": {"proposal": {"type": "string"}},
            "required": ["proposal"],
            "additionalProperties": False,
        },
        "handler": propose_long_term,
    },
}


def debug(text):
    with (ROOT / "adapter" / "mcp-debug.log").open("a", encoding="utf-8") as handle:
        handle.write(text + "\n")


def send(message):
    body = json.dumps(message, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(body + b"\n")
    sys.stdout.buffer.flush()


def handle(message):
    method = message.get("method")
    if method == "initialize":
        return {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "factorio-mira", "version": "0.1.0"},
        }
    if method == "tools/list":
        return {
            "tools": [
                {"name": name, "description": tool["description"], "inputSchema": tool["inputSchema"]}
                for name, tool in TOOLS.items()
            ]
        }
    if method == "tools/call":
        params = message.get("params") or {}
        try:
            result = TOOLS[params["name"]]["handler"](params.get("arguments") or {})
            return text_result(result)
        except Exception as exc:
            return text_result({"error": str(exc)}, is_error=True)
    if method in ("notifications/initialized", "initialized"):
        return None
    raise ValueError(f"unknown method: {method}")


def message_from_line(line):
    text = line.decode("utf-8", errors="replace").strip()
    debug("line:" + text[:500])
    if text.startswith("{"):
        return json.loads(text)
    headers = {}
    current = line
    while current not in (b"\r\n", b"\n"):
        key, value = current.decode("ascii").split(":", 1)
        headers[key.lower()] = value.strip()
        current = sys.stdin.buffer.readline()
    length = int(headers["content-length"])
    raw = sys.stdin.buffer.read(length)
    debug("request:" + raw.decode("utf-8", errors="replace"))
    return json.loads(raw.decode("utf-8"))


def main():
    debug("server-started")
    while True:
        line = sys.stdin.buffer.readline()
        if line == b"":
            return 0
        message = message_from_line(line)
        if "id" not in message:
            continue
        try:
            result = handle(message)
            if result is not None:
                send({"jsonrpc": "2.0", "id": message["id"], "result": result})
        except Exception as exc:
            send({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32603, "message": str(exc)}})


if __name__ == "__main__":
    sys.exit(main())
