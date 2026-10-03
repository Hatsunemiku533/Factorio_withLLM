"""Run one bounded, interruptible sequence of fresh Mira sessions."""

import json
import os
import secrets
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import bridge_probe

ROOT = Path(__file__).resolve().parents[1]
RUNS = ROOT / "runs"
PYTHON = Path(r"F:\vscode\minicode\python.exe")
OPENCODE = r"F:\opencode\node_modules\opencode-ai\bin\opencode.exe"
TASK = """Mira，现在开始自己玩一会儿。

首先想办法建立一个能够持续一段时间生产 iron plate 的最小系统。
不要依赖人类手动帮你完成步骤。

当你认为铁板生产已经稳定后，用剩余时间自己选择一个合理的小改进继续做。

不要为了扩张而破坏 Stellan 的建筑或角色。
如果遇到你当前能力无法解决的问题，记录 blocker 并安全停下来。

这是一个新的短 episode。先观察，只推进当前最有用的一小步。结束前调用 episode_finish：可以继续时 status 用 continue，无法解决时用 blocker，并写清事实与下一步。不要在本 episode 中无限继续。"""


class RunBudget:
    def __init__(self, started, wall_seconds=20 * 60, hard_seconds=25 * 60, episodes=8, failures=3):
        self.started = started
        self.wall_seconds = wall_seconds
        self.hard_seconds = hard_seconds
        self.episodes = episodes
        self.failures = failures
        self.episode_count = 0
        self.failure_counts = {}

    def remaining(self, now=None):
        now = time.time() if now is None else now
        return self.started + self.hard_seconds - now

    def expired(self, now=None):
        return self.remaining(now) <= 0 or self.episode_count >= self.episodes

    def record_failure(self, reason):
        key = " ".join(str(reason).split())[:240]
        self.failure_counts[key] = self.failure_counts.get(key, 0) + 1
        return self.failure_counts[key] >= self.failures


def production_evidence(snapshot):
    furnaces = [item for item in snapshot["machines"] if item["name"] == "stone-furnace"]
    drills = [item for item in snapshot["machines"] if item["name"] == "burner-mining-drill"]
    return {
        "furnace_count": len(furnaces),
        "drill_count": len(drills),
        "products_finished": sum(item.get("products_finished") or 0 for item in furnaces),
        "fuel_items": sum(sum((item.get("fuel") or {}).values()) for item in furnaces + drills),
        "input_items": sum(sum((item.get("input") or {}).values()) for item in furnaces),
        "output_items": sum(sum((item.get("output") or {}).values()) for item in furnaces),
        "mining_targets": [item.get("mining_target") for item in drills],
    }


def acceptance(before, after):
    gained = after["products_finished"] - before["products_finished"]
    fueled = after["fuel_items"] > 0
    supplied = after["input_items"] > 0 or any(after["mining_targets"])
    return gained >= 10 and after["drill_count"] >= 1 and fueled and supplied


def stop_tree(process):
    if process.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        process.send_signal(signal.SIGTERM)


def run_episode(run_dir, index, deadline):
    log_path = run_dir / f"episode-{index:02d}.jsonl"
    env = os.environ.copy()
    env["MIRA_RUN_TOKEN"] = env["MIRA_RUN_TOKEN"]
    env["MIRA_RUN_DEADLINE"] = str(deadline)
    command = [OPENCODE, "run", "--dir", str(ROOT), "--agent", "mira", "--format", "json", "--title", f"phase4ab-{index}", TASK]
    with log_path.open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.PIPE, text=True, encoding="utf-8")
        while process.poll() is None:
            if time.time() >= deadline:
                stop_tree(process)
                process.wait(timeout=20)
                return {"status": "timeout", "log": str(log_path)}
            time.sleep(1)
    failures = []
    finish = None
    for line in log_path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("{"):
            continue
        event = json.loads(line)
        if event.get("type") != "tool_use":
            continue
        part = event.get("part", {})
        state = part.get("state", {})
        output = str(state.get("error") or state.get("output") or "")
        if state.get("status") == "error" or '"isError": true' in output or '"isError":true' in output:
            failures.append(output[:500])
        if part.get("tool") == "episode_finish" and state.get("status") == "completed":
            finish = json.loads(state.get("output", "{}")).get("content", [{}])[0].get("text")
    return {"status": "finished", "log": str(log_path), "failures": failures, "finish": finish}


def safe_stop():
    try:
        return bridge_probe.call_remote("end_run")
    except Exception as exc:
        return {"error": str(exc)}


def main():
    started = time.time()
    budget = RunBudget(started)
    token = "phase4ab-" + secrets.token_hex(8)
    run_dir = RUNS / datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir.mkdir(parents=True, exist_ok=False)
    os.environ["MIRA_RUN_TOKEN"] = token
    before = production_evidence(bridge_probe.call_remote("production_snapshot"))
    bridge_probe.call_remote("begin_run", {"token": token, "duration_seconds": budget.hard_seconds})
    outcome = "timeout"
    try:
        while not budget.expired():
            budget.episode_count += 1
            episode_deadline = min(started + budget.hard_seconds, time.time() + max(60, budget.remaining() / 2))
            result = run_episode(run_dir, budget.episode_count, episode_deadline)
            (run_dir / "episodes.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
            if any(budget.record_failure(item) for item in result.get("failures", [])):
                outcome = "repeated-failure"
                break
            if result.get("finish") and '"episode_status": "blocker"' in result["finish"]:
                outcome = "blocker"
                break
            if time.time() >= started + budget.wall_seconds:
                outcome = "wall-clock"
                break
    finally:
        stopped = safe_stop()
        after = production_evidence(bridge_probe.call_remote("production_snapshot"))
        report = {"outcome": outcome, "before": before, "after": after, "accepted": acceptance(before, after), "stopped": stopped}
        (run_dir / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
