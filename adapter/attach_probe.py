"""Attach to a running Factorio server and read its state.

This probe imports only factorio_rcon. It must never instantiate FLE's
FactorioInstance or start FLE's MCP server.
"""

import json
import sys
from pathlib import Path

from factorio_rcon import RCONClient

ROOT = Path(__file__).resolve().parents[1]
PASSWORD_PATH = ROOT / "server" / "config" / "rconpw"
HOST = "127.0.0.1"
PORT = 27015

READ_LUA = r"""
local surface = game.surfaces[1]
local players = {}
for _, player in pairs(game.players) do
  players[#players + 1] = {
    name = player.name,
    connected = player.connected,
    controller = player.controller_type,
  }
end

local furnace_positions = {}
local counts = {}
for _, entity in pairs(surface.find_entities_filtered({force = "player"})) do
  counts[entity.name] = (counts[entity.name] or 0) + 1
  if entity.name == "stone-furnace" then
    furnace_positions[#furnace_positions + 1] = {
      x = entity.position.x,
      y = entity.position.y,
    }
  end
end

local summary = {
  tick = game.tick,
  speed = game.speed,
  surface = surface.name,
  player_count = #game.players,
  players = players,
  player_force_entity_total = surface.count_entities_filtered({force = "player"}),
  entity_counts = counts,
  stone_furnaces = furnace_positions,
}
rcon.print(helpers.table_to_json(summary))
"""


def snapshot():
    password = PASSWORD_PATH.read_text(encoding="utf-8").strip()
    if not password:
        raise RuntimeError("RCON password file is empty")

    client = RCONClient(HOST, PORT, password, timeout=10)
    try:
        command = f"/sc {READ_LUA}"
        response = client.send_command(command)
        # Factorio blocks the first Lua command until it is repeated,
        # because enabling the Lua console disables achievements.
        if response is None:
            response = client.send_command(command)
    finally:
        client.close()
    return json.loads(response)


def main():
    before = snapshot()
    after = snapshot()
    speed_unchanged = before["speed"] == after["speed"]
    players_unchanged = before["players"] == after["players"]
    furnaces_unchanged = before["stone_furnaces"] == after["stone_furnaces"]
    counts_unchanged = before["entity_counts"] == after["entity_counts"]
    result = {
        "before": before,
        "after": after,
        "checks": {
            "speed_unchanged": speed_unchanged,
            "players_unchanged": players_unchanged,
            "stone_furnaces_unchanged": furnaces_unchanged,
            "entity_counts_unchanged": counts_unchanged,
            "stone_furnace_present": len(after["stone_furnaces"]) > 0,
        },
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not all(result["checks"].values()):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
