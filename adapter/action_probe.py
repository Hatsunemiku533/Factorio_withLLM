"""Run one visible walk-and-place action on the test server."""

import json
import sys
import time

import bridge_probe

TARGET = {"x": 20, "y": 0}
PLACE = {"x": 22, "y": 0}


def main():
    start = bridge_probe.call_remote("agent_status")
    bridge_probe.call_remote("give_stone_furnace")
    bridge_probe.call_remote("walk_to", TARGET)
    deadline = time.time() + 30
    last = None
    while time.time() < deadline:
        status = bridge_probe.call_remote("movement_status")
        point = (round(status["agent_x"], 2), round(status["agent_y"], 2), status["state"])
        if point != last:
            print(json.dumps(status, ensure_ascii=False), flush=True)
            last = point
        if status["state"] in ("arrived", "failed", "idle"):
            break
        time.sleep(0.5)
    else:
        bridge_probe.call_remote("stop_agent")
        raise RuntimeError("movement timed out")

    if status["state"] != "arrived":
        raise RuntimeError(f"movement failed: {status['reason']}")
    if status["agent_unit_number"] != start["unit_number"]:
        raise RuntimeError("AI character changed during movement")

    placed = bridge_probe.call_remote("place_stone_furnace", PLACE)
    print(json.dumps({"start": start, "placed": placed}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
