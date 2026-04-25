"""Выполнение shell-команд на локальном Keenetic (Entware)."""
from __future__ import annotations

import os
import subprocess
from datetime import datetime, timezone
from typing import Any

# Entware + системные пути Keenetic
_DEFAULT_PATH = "/opt/bin:/opt/sbin:/usr/sbin:/sbin:/bin:/usr/bin"


def run_shell(command: str, timeout: int = 300) -> dict[str, Any]:
    if not command or not command.strip():
        return {"ok": False, "output": "", "msg": "Пустая команда"}
    cur = os.environ.get("PATH", "")
    extra = ":" + _DEFAULT_PATH if cur else _DEFAULT_PATH
    if not any(x in cur for x in ("/opt/bin", "/opt/sbin")):
        cur = (cur + extra) if cur else _DEFAULT_PATH
    env = {**os.environ, "PATH": cur or _DEFAULT_PATH}
    try:
        p = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
        out = (p.stdout or "") + (("\n--- stderr ---\n" + p.stderr) if p.stderr else "")
        out = out.strip()[:120_000]
        ok = p.returncode == 0
        return {"ok": ok, "output": out, "msg": f"exit {p.returncode}"}
    except subprocess.TimeoutExpired:
        return {"ok": False, "output": "", "msg": f"timeout {timeout}s"}
    except Exception as e:
        return {"ok": False, "output": "", "msg": str(e)[:500]}


def touch_item(items: list[dict], item_id: str, result: dict[str, Any]) -> None:
    now = datetime.now(timezone.utc).astimezone().replace(microsecond=0).isoformat()
    for it in items:
        if it.get("id") == item_id:
            it["last_run"] = now
            it["last_ok"] = result.get("ok")
            parts = []
            if result.get("msg"):
                parts.append(result["msg"])
            if result.get("output"):
                parts.append(result["output"])
            it["last_output"] = "\n".join(parts).strip()[:100_000]
            break
