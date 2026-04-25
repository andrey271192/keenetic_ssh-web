#!/opt/bin/python3
"""keenetic_ssh-web — веб-панель локальных CLI-команд на Keenetic (Entware), порт 2001."""
from __future__ import annotations

import logging
import os
import threading
import time
from pathlib import Path

from flask import Flask, Response, jsonify, request

from auth import is_token_valid, issue_token, keenetic_validate_any, revoke_token
from brand import inject_brand
from executor import run_items
from store import load_store, new_item, save_store

logging.basicConfig(level=logging.INFO, format="%(asctime)s [kssh] %(levelname)s %(message)s")
log = logging.getLogger("kssh")

APP_DIR = Path(__file__).resolve().parent

WEB_PASSWORD = os.environ.get("WEB_PASSWORD", "").strip()
AUTHOR_TG = os.environ.get("AUTHOR_TELEGRAM_USERNAME", "Iot_andrey").strip().lstrip("@") or "Iot_andrey"
ALLOWED_IPS_RAW = os.environ.get("ALLOWED_IPS", "").strip()
ALLOWED_IPS = {x.strip() for x in ALLOWED_IPS_RAW.split(",") if x.strip()} if ALLOWED_IPS_RAW else set()
CMD_TIMEOUT = int(os.environ.get("CMD_TIMEOUT", "300"))

ROUTER_HOST_RAW = os.environ.get("ROUTER_HOST", "http://127.0.0.1").strip()
ROUTER_HOSTS = [h.strip() for h in ROUTER_HOST_RAW.split(",") if h.strip()]
ROUTER_LOGIN_DEFAULT = os.environ.get("ROUTER_LOGIN", "admin").strip() or "admin"
ROUTER_TIMEOUT = float(os.environ.get("ROUTER_TIMEOUT", "5") or "5")

_scheduler_started = threading.Lock()
_last_batch = 0.0


def _client_ip() -> str:
    xff = request.headers.get("X-Forwarded-For", "")
    if xff:
        return xff.split(",")[0].strip()
    return request.remote_addr or ""


def _ip_allowed() -> bool:
    if not ALLOWED_IPS:
        return True
    return _client_ip() in ALLOWED_IPS


def _token() -> str:
    return request.headers.get("X-Session-Token", "").strip()


def _auth_ok() -> bool:
    return is_token_valid(_token())


def _require():
    if not _ip_allowed():
        return jsonify({"error": "IP не в списке ALLOWED_IPS"}), 403
    if not _auth_ok():
        return jsonify({"error": "Нужен вход"}), 401
    return None


def _validate_credentials(login: str, password: str) -> bool:
    if ROUTER_HOSTS:
        try:
            if keenetic_validate_any(ROUTER_HOSTS, login, password, timeout=ROUTER_TIMEOUT):
                return True
        except Exception:
            log.exception("router auth call failed")
    if WEB_PASSWORD and password == WEB_PASSWORD:
        log.info("auth: вход по WEB_PASSWORD (мастер-пароль)")
        return True
    return False


def create_app() -> Flask:
    app = Flask(__name__, static_folder="static", template_folder="templates")

    @app.after_request
    def no_store(resp: Response):
        resp.headers["Cache-Control"] = "no-store"
        return resp

    @app.get("/")
    def index():
        raw = (APP_DIR / "templates" / "index.html").read_text(encoding="utf-8")
        return Response(inject_brand(raw, AUTHOR_TG), mimetype="text/html; charset=utf-8")

    @app.get("/api/auth")
    def auth_check():
        if not _ip_allowed():
            return jsonify({"ok": False, "error": "IP не разрешён"}), 403
        info = {
            "router_auth": bool(ROUTER_HOSTS),
            "router_hosts": ROUTER_HOSTS,
            "default_login": ROUTER_LOGIN_DEFAULT,
            "password_fallback": bool(WEB_PASSWORD),
        }
        if not ROUTER_HOSTS and not WEB_PASSWORD:
            return jsonify({"ok": False, "error": "Задайте ROUTER_HOST или WEB_PASSWORD в .env", **info}), 503
        return jsonify({"ok": _auth_ok(), **info})

    @app.post("/api/login")
    def api_login():
        if not _ip_allowed():
            return jsonify({"ok": False, "error": "IP не разрешён"}), 403
        body = request.get_json(silent=True) or {}
        login = (str(body.get("login") or ROUTER_LOGIN_DEFAULT)).strip() or ROUTER_LOGIN_DEFAULT
        password = str(body.get("password") or "")
        if not password:
            return jsonify({"ok": False, "error": "Пустой пароль"}), 400
        if not _validate_credentials(login, password):
            log.warning("login fail: ip=%s login=%s router_hosts=%s", _client_ip(), login, ROUTER_HOSTS)
            return jsonify({"ok": False, "error": "Неверный логин или пароль"}), 401
        token = issue_token()
        log.info("login ok: ip=%s login=%s", _client_ip(), login)
        return jsonify({"ok": True, "token": token})

    @app.post("/api/logout")
    def api_logout():
        revoke_token(_token())
        return jsonify({"ok": True})

    @app.get("/api/config")
    def get_cfg():
        e = _require()
        if e:
            return e
        return jsonify(load_store())

    @app.post("/api/interval")
    def set_interval():
        e = _require()
        if e:
            return e
        body = request.get_json(silent=True) or {}
        minutes = int(body.get("minutes", 0))
        minutes = max(0, min(minutes, 10080))
        data = load_store()
        data["interval_minutes"] = minutes
        save_store(data)
        return jsonify({"ok": True, "interval_minutes": minutes})

    @app.post("/api/items")
    def add_item():
        e = _require()
        if e:
            return e
        body = request.get_json(silent=True) or {}
        name = str(body.get("name", "")).strip()
        command = str(body.get("command", "")).strip()
        note = str(body.get("note", "")).strip()
        if not name or not command:
            return jsonify({"error": "Название и команда обязательны"}), 400
        data = load_store()
        item = new_item(
            name,
            command,
            note=note,
            enabled=bool(body.get("enabled", True)),
            schedule=bool(body.get("schedule", False)),
        )
        data.setdefault("items", []).append(item)
        save_store(data)
        return jsonify({"ok": True, "item": item})

    @app.patch("/api/items/<item_id>")
    def patch_item(item_id: str):
        e = _require()
        if e:
            return e
        body = request.get_json(silent=True) or {}
        data = load_store()
        for it in data.get("items", []):
            if it.get("id") != item_id:
                continue
            if "name" in body and body["name"] is not None:
                it["name"] = str(body["name"]).strip() or it["name"]
            if "command" in body and body["command"] is not None:
                it["command"] = str(body["command"]).strip()
            if "note" in body and body["note"] is not None:
                it["note"] = str(body["note"]).strip()
            if "enabled" in body and body["enabled"] is not None:
                it["enabled"] = bool(body["enabled"])
            if "schedule" in body and body["schedule"] is not None:
                it["schedule"] = bool(body["schedule"])
            save_store(data)
            return jsonify({"ok": True, "item": it})
        return jsonify({"error": "Не найдено"}), 404

    @app.delete("/api/items/<item_id>")
    def del_item(item_id: str):
        e = _require()
        if e:
            return e
        data = load_store()
        items = [x for x in data.get("items", []) if x.get("id") != item_id]
        if len(items) == len(data.get("items", [])):
            return jsonify({"error": "Не найдено"}), 404
        data["items"] = items
        save_store(data)
        return jsonify({"ok": True})

    @app.post("/api/run-all")
    def run_all():
        e = _require()
        if e:
            return e
        results = run_items(None, False, timeout=CMD_TIMEOUT)
        return jsonify({"ok": True, "results": results})

    @app.post("/api/run/<item_id>")
    def run_one(item_id: str):
        e = _require()
        if e:
            return e
        results = run_items([item_id], False, timeout=CMD_TIMEOUT)
        if not results:
            return jsonify({"error": "Не найдено или выключено"}), 404
        return jsonify({"ok": True, "result": results[0]})

    return app


app = create_app()


def _scheduler_loop():
    global _last_batch
    _last_batch = time.monotonic()
    while True:
        try:
            time.sleep(60)
            data = load_store()
            iv = int(data.get("interval_minutes") or 0)
            if iv <= 0:
                continue
            now = time.monotonic()
            if now - _last_batch < iv * 60:
                continue
            ids = [
                it["id"]
                for it in data.get("items", [])
                if it.get("id") and it.get("enabled") and it.get("schedule")
            ]
            if not ids:
                _last_batch = now
                continue
            log.info("scheduled run: %d command(s)", len(ids))
            run_items(ids, True, timeout=CMD_TIMEOUT)
            _last_batch = time.monotonic()
        except Exception:
            log.exception("scheduler")


def _ensure_scheduler():
    with _scheduler_started:
        if getattr(_ensure_scheduler, "_done", False):
            return
        t = threading.Thread(target=_scheduler_loop, daemon=True, name="kssh-sched")
        t.start()
        _ensure_scheduler._done = True  # type: ignore[attr-defined]


@app.before_request
def _start_scheduler_once():
    _ensure_scheduler()


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "2001"))
    print(f"keenetic_ssh-web http://0.0.0.0:{port} (dev; на роутере — waitress)")
    app.run(host="0.0.0.0", port=port, debug=False, threaded=True)
