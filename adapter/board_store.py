"""Append-only local message board shared by world participants."""

import json
import os
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "board"
MESSAGES = BOARD / "messages.jsonl"
CURSORS = BOARD / "cursors.json"
AUTHORS = {"mira", "stellan"}
RECIPIENTS = {"mira", "stellan", "all"}
MAX_TEXT = 1000


def _clean(value, name, limit):
    if not isinstance(value, str):
        raise ValueError(f"{name} must be text")
    text = " ".join(value.replace("\r\n", "\n").split())
    if not text:
        raise ValueError(f"{name} is empty")
    if len(text.encode("utf-8")) > limit:
        raise ValueError(f"{name} exceeds {limit} bytes")
    return text


def _read_valid(handle):
    messages = []
    for line_number, line in enumerate(handle, 1):
        if not line.strip():
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"board line {line_number} is damaged; earlier messages were preserved") from exc
        if not isinstance(item, dict) or not isinstance(item.get("id"), int):
            raise ValueError(f"board line {line_number} is damaged; earlier messages were preserved")
        messages.append(item)
    return messages


def _lock(handle):
    if os.name == "nt":
        import msvcrt
        handle.seek(0)
        msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
    else:
        import fcntl
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)


def _unlock(handle):
    if os.name == "nt":
        import msvcrt
        handle.seek(0)
        msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
    else:
        import fcntl
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def post(author, recipient, text):
    author = _clean(author, "author", 40)
    recipient = _clean(recipient, "recipient", 40)
    text = _clean(text, "text", MAX_TEXT)
    if author not in AUTHORS:
        raise ValueError("unknown author")
    if recipient not in RECIPIENTS:
        raise ValueError("recipient must be mira, stellan, or all")
    BOARD.mkdir(parents=True, exist_ok=True)
    flags = os.O_CREAT | os.O_RDWR
    descriptor = os.open(MESSAGES, flags)
    handle = os.fdopen(descriptor, "r+", encoding="utf-8")
    try:
        _lock(handle)
        handle.seek(0)
        messages = _read_valid(handle)
        message = {
            "id": (messages[-1]["id"] + 1) if messages else 1,
            "time": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "author": author,
            "to": recipient,
            "text": text,
        }
        handle.seek(0, os.SEEK_END)
        handle.write(json.dumps(message, ensure_ascii=False, separators=(",", ":")) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
        return message
    finally:
        _unlock(handle)
        handle.close()


def read_for(agent_id, limit=10, mark_delivered=True):
    agent_id = _clean(agent_id, "agent", 40)
    if agent_id not in AUTHORS:
        raise ValueError("unknown agent")
    limit = max(1, min(20, int(limit)))
    BOARD.mkdir(parents=True, exist_ok=True)
    MESSAGES.touch(exist_ok=True)
    descriptor = os.open(MESSAGES, os.O_RDWR)
    handle = os.fdopen(descriptor, "r+", encoding="utf-8")
    try:
        _lock(handle)
        handle.seek(0)
        messages = _read_valid(handle)
        cursors = {}
        if CURSORS.exists():
            try:
                cursors = json.loads(CURSORS.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                cursors = {}
        if not isinstance(cursors, dict):
            cursors = {}
        cursor = cursors.get(agent_id, 0)
        if isinstance(cursor, bool) or not isinstance(cursor, int) or cursor < 0:
            raise ValueError("cursor is invalid")
        visible = [item for item in messages if item["id"] > cursor and item["to"] in {agent_id, "all"}]
        selected = visible[:limit]
        if mark_delivered and selected:
            cursors[agent_id] = selected[-1]["id"]
            temporary = CURSORS.with_suffix(".tmp")
            temporary.write_text(json.dumps(cursors, ensure_ascii=False, indent=2), encoding="utf-8")
            temporary.replace(CURSORS)
        return {"messages": selected, "more": len(visible) > len(selected)}
    finally:
        _unlock(handle)
        handle.close()


def recent(limit=20):
    limit = max(1, min(50, int(limit)))
    if not MESSAGES.exists():
        return []
    with MESSAGES.open("r", encoding="utf-8") as handle:
        return _read_valid(handle)[-limit:]
