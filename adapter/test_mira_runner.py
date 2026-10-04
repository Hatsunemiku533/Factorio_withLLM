import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import mira_runner


class RunBudgetTests(unittest.TestCase):
    def test_default_episode_budget_is_ten_minutes(self):
        budget = mira_runner.RunBudget(started=1_000)

        self.assertEqual(budget.episode_max_seconds, 600)
        self.assertEqual(budget.episode_deadline(now=1_100), 1_700)
        self.assertEqual(budget.episode_deadline(now=9_050), 9_100)

    def test_episode_deadline_is_fixed_and_capped_by_run_hard_limit(self):
        budget = mira_runner.RunBudget(
            started=1_000,
            wall_seconds=7_200,
            hard_seconds=8_100,
            episode_max_seconds=300,
        )

        self.assertEqual(budget.episode_deadline(now=1_100), 1_400)
        self.assertEqual(budget.episode_deadline(now=9_050), 9_100)

    def test_three_consecutive_episode_timeouts_degrade_health(self):
        budget = mira_runner.RunBudget(started=1_000)

        self.assertFalse(budget.record_episode_result("episode_time_budget", finished=False))
        self.assertFalse(budget.record_episode_result("episode_time_budget", finished=False))
        self.assertTrue(budget.record_episode_result("episode_time_budget", finished=False))

    def test_normal_finish_resets_timeout_streak(self):
        budget = mira_runner.RunBudget(started=1_000)
        budget.record_episode_result("episode_time_budget", finished=False)
        budget.record_episode_result("finished", finished=True)

        self.assertFalse(budget.record_episode_result("episode_time_budget", finished=False))


class FailureIdentityTests(unittest.TestCase):
    def test_same_error_on_different_targets_does_not_share_a_fuse(self):
        reason = "resource does not exist at target"
        first = mira_runner.failure_identity(
            "factorio-mira_mine_resource",
            {"resource": "iron-ore", "x": -69.5, "y": -11.5, "count": 1},
            reason,
        )
        second = mira_runner.failure_identity(
            "factorio-mira_mine_resource",
            {"resource": "iron-ore", "x": -68.5, "y": -12.5, "count": 1},
            reason,
        )

        self.assertNotEqual(first, second)

    def test_irrelevant_count_does_not_hide_same_target_loop(self):
        reason = "resource does not exist at target"
        first = mira_runner.failure_identity(
            "factorio-mira_mine_resource",
            {"resource": "coal", "x": 1.5, "y": 2.5, "count": 1},
            reason,
        )
        second = mira_runner.failure_identity(
            "factorio-mira_mine_resource",
            {"resource": "coal", "x": 1.5, "y": 2.5, "count": 10},
            reason,
        )

        self.assertEqual(first, second)


class ContextTests(unittest.TestCase):
    def test_fixed_context_is_bounded_and_reports_component_sizes(self):
        text, sizes = mira_runner.build_fixed_context(
            "L" * 9_000,
            "C" * 9_000,
            {"messages": [{"id": 1, "author": "stellan", "to": "mira", "text": "hello"}], "more": False},
        )

        self.assertEqual(sizes["long_term_chars"], 8_000)
        self.assertEqual(sizes["current_chars"], 6_000)
        self.assertEqual(sizes["board_messages"], 1)
        self.assertNotIn("memory/log", text)


class EpisodeLogTests(unittest.TestCase):
    def test_parser_extracts_finish_failures_and_token_usage(self):
        events = [
            {
                "type": "tool_use",
                "part": {
                    "tool": "factorio-mira_mine_resource",
                    "state": {
                        "status": "error",
                        "input": {"resource": "iron-ore", "x": 1.5, "y": 2.5, "count": 1},
                        "error": '{"error":"resource does not exist at target"}',
                    },
                },
            },
            {
                "type": "tool_use",
                "part": {
                    "tool": "factorio-mira_episode_finish",
                    "state": {
                        "status": "completed",
                        "output": json.dumps({"content": [{"text": '{"episode_status":"continue"}'}]}),
                    },
                },
            },
            {
                "type": "step_finish",
                "part": {
                    "tokens": {
                        "input": 100,
                        "output": 20,
                        "reasoning": 30,
                        "cache": {"read": 400, "write": 0},
                    }
                },
            },
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "episode.jsonl"
            path.write_text("\n".join(json.dumps(event) for event in events), encoding="utf-8")
            result = mira_runner.parse_episode_log(path)

        self.assertEqual(result["finish_status"], "continue")
        self.assertEqual(len(result["failures"]), 1)
        self.assertEqual(result["tokens"]["cache_read"], 400)
        self.assertEqual(result["tokens"]["reasoning"], 30)

    def test_parser_accepts_direct_mcp_finish_output(self):
        event = {
            "type": "tool_use",
            "part": {
                "tool": "factorio-mira_episode_finish",
                "state": {
                    "status": "completed",
                    "input": {"status": "continue", "summary": "ok", "current_goal": "next"},
                    "output": json.dumps({"episode_status": "continue", "summary": "ok", "current_goal": "next"}),
                },
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "episode.jsonl"
            path.write_text(json.dumps(event), encoding="utf-8")
            result = mira_runner.parse_episode_log(path)

        self.assertEqual(result["finish_status"], "continue")


class ProcessErrorTests(unittest.TestCase):
    def test_provider_metadata_does_not_turn_permission_error_into_outage(self):
        stderr = (
            "stream providerID=ustc modelID=deepseek-flash\n"
            "The user has specified a rule which prevents you from using this specific tool call"
        )

        self.assertEqual(mira_runner.classify_process_error(stderr), "subprocess_error")

    def test_explicit_provider_unavailable_is_an_outage(self):
        self.assertEqual(
            mira_runner.classify_process_error("provider unavailable (simulated)"),
            "provider_unavailable",
        )


if __name__ == "__main__":
    unittest.main()
