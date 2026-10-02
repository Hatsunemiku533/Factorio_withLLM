"""Call the save-safe bridge through direct RCON.

The probe imports only factorio_rcon. It never creates a FactorioInstance
or starts FLE's MCP server.
"""

import json
import sys
from pathlib import Path

from factorio_rcon import RCONClient

ROOT = Path(__file__).resolve().parents[1]
PASSWORD_PATH = ROOT / "server-test" / "config" / "rconpw"
HOST = "127.0.0.1"
PORT = 27115

READ_LUA = r"""
local summary = remote.call("save_safe_bridge", "get_entities", {
  surface = "nauvis",
  force = "player",
  x = 0,
  y = 0,
  radius = 32,
})
local players = {}
local characters = {}
for _, player in pairs(game.players) do
  local character = player.character
  players[#players + 1] = {
    name = player.name,
    connected = player.connected,
    controller = player.controller_type,
    character_unit_number = character and character.unit_number or nil,
  }
end
for _, entity in pairs(game.surfaces[1].find_entities_filtered({type = "character"})) do
  characters[#characters + 1] = {
    unit_number = entity.unit_number,
    player = entity.player and entity.player.name or nil,
  }
end
summary.players = players
summary.characters = characters
rcon.print(helpers.table_to_json(summary))
"""


def connect():
    password = PASSWORD_PATH.read_text(encoding="utf-8").strip()
    if not password:
        raise RuntimeError("test RCON password file is empty")
    return RCONClient(HOST, PORT, password, timeout=20)


def save_world():
    client = connect()
    try:
        client.send_command("/server-save")
    finally:
        client.close()


def query():
    client = connect()
    try:
        command = f"/sc {READ_LUA}"
        response = client.send_command(command)
        if response is None:
            response = client.send_command(command)
    finally:
        client.close()
    if response is None:
        raise RuntimeError("bridge query returned no response")
    return json.loads(response)


def main():
    if "--save" in sys.argv:
        save_world()
        print("saved")
        return 0

    result = query()
    names = [entity["name"] for entity in result["entities"]]
    checks = {
        "stone_furnace_present": "stone-furnace" in names,
        "speed_is_one": result["speed"] == 1,
        "no_unattached_character": all(character["player"] is not None for character in result["characters"]),
    }
    print(json.dumps({"result": result, "checks": checks}, ensure_ascii=False, indent=2))
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
