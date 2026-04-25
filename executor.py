"""Запуск команд из store.json (API и фоновый планировщик)."""
from __future__ import annotations

from typing import Any

from runner import run_shell, touch_item
from store import load_store, save_store


def run_items(
    item_ids: list[str] | None,
    only_scheduled: bool,
    *,
    timeout: int,
) -> list[dict[str, Any]]:
    """
    item_ids=None — все с enabled (ручной «выполнить всё»).
    only_scheduled=True — только enabled+schedule (фон).
    """
    data = load_store()
    items = list(data.get("items") or [])
    id_set = set(item_ids) if item_ids is not None else None
    out: list[dict[str, Any]] = []
    changed = False
    for it in items:
        iid = it.get("id")
        if not iid:
            continue
        if id_set is not None and iid not in id_set:
            continue
        if not it.get("enabled", True):
            if id_set is not None:
                out.append(
                    {
                        "id": iid,
                        "name": it.get("name"),
                        "ok": False,
                        "output": "",
                        "msg": "Выключено (ВКЛ)",
                    }
                )
            continue
        if only_scheduled and not it.get("schedule"):
            continue
        res = run_shell(it.get("command") or "", timeout=timeout)
        touch_item(items, iid, res)
        changed = True
        out.append({"id": iid, "name": it.get("name"), **res})
    if changed:
        data["items"] = items
        save_store(data)
    return out
