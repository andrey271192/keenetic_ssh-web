"""JSON-хранилище команд (локально на роутере)."""
from __future__ import annotations

import json
import threading
import uuid
from pathlib import Path
from typing import Any

_lock = threading.Lock()
_DEFAULT = {"interval_minutes": 0, "items": []}


def store_path() -> Path:
    base = Path(__file__).resolve().parent
    p = base / "data" / "store.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def load_store() -> dict[str, Any]:
    path = store_path()
    if not path.exists():
        return json.loads(json.dumps(_DEFAULT))
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return json.loads(json.dumps(_DEFAULT))
    if not isinstance(data, dict):
        return json.loads(json.dumps(_DEFAULT))
    data.setdefault("interval_minutes", 0)
    data.setdefault("items", [])
    if not isinstance(data["items"], list):
        data["items"] = []
    return data


def save_store(data: dict[str, Any]) -> None:
    path = store_path()
    tmp = path.with_suffix(".tmp")
    text = json.dumps(data, ensure_ascii=False, indent=2)
    with _lock:
        tmp.write_text(text, encoding="utf-8")
        tmp.replace(path)


def new_item(
    name: str,
    command: str,
    note: str = "",
    enabled: bool = True,
    schedule: bool = False,
) -> dict[str, Any]:
    return {
        "id": uuid.uuid4().hex,
        "name": name.strip(),
        "command": command.strip(),
        "note": (note or "").strip(),
        "enabled": bool(enabled),
        "schedule": bool(schedule),
        "last_run": None,
        "last_ok": None,
        "last_output": "",
    }
