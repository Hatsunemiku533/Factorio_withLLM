import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import mira_mcp


class CoreFactoryPermissionTests(unittest.TestCase):
    def test_place_item_accepts_any_placeable_name_for_bridge_validation(self):
        with patch.object(mira_mcp, "call_remote", return_value={"placed": True}) as remote:
            result = mira_mcp.place_item({"item": "iron-chest", "x": 1, "y": 2})

        self.assertTrue(result["placed"])
        remote.assert_called_once_with(
            "place_item",
            {"item": "iron-chest", "x": 1.0, "y": 2.0, "direction": "north"},
        )

    def test_main_inventory_is_available_for_containers(self):
        with patch.object(mira_mcp, "call_remote", return_value={"inserted": 1}) as remote:
            mira_mcp.insert_into_entity({
                "unit_number": 42,
                "item": "iron-plate",
                "count": 1,
                "inventory_kind": "main",
            })

        remote.assert_called_once_with(
            "insert_into_entity",
            {"unit_number": 42, "item": "iron-plate", "count": 1, "inventory_kind": "main"},
        )

    def test_take_supports_main_inventory(self):
        with patch.object(mira_mcp, "call_remote", return_value={"taken": 1}) as remote:
            mira_mcp.take_from_entity({
                "unit_number": 42,
                "item": "iron-plate",
                "count": 1,
                "inventory_kind": "main",
            })

        remote.assert_called_once_with(
            "take_from_entity",
            {"unit_number": 42, "item": "iron-plate", "count": 1, "inventory_kind": "main"},
        )

    def test_dismantle_entity_is_a_guarded_mutation(self):
        self.assertIn("dismantle_entity", mira_mcp.MUTATING_FUNCTIONS)
        with patch.object(mira_mcp, "call_remote", return_value={"mined": True}) as remote:
            result = mira_mcp.dismantle_entity({"unit_number": 42})

        self.assertTrue(result["mined"])
        remote.assert_called_once_with("dismantle_entity", {"unit_number": 42})


if __name__ == "__main__":
    unittest.main()
