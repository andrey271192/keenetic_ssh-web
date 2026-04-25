"""Аутентификация против HTTP-админки Keenetic (NDM) + сессионные токены.

Используется протокол NDM:
1) GET /auth → 401 + заголовки X-NDM-Realm и X-NDM-Challenge.
2) hash = sha256(challenge + md5(login:realm:password)).
3) POST /auth с JSON {"login": ..., "password": hash} → 200 OK при успехе.

Не требует внешних библиотек (urllib стандартной библиотеки).
"""
from __future__ import annotations

import hashlib
import http.cookiejar
import json
import logging
import secrets
import threading
import time
import urllib.error
import urllib.request

log = logging.getLogger("kssh.auth")


def _normalize_host(host: str) -> str:
    h = (host or "").strip().rstrip("/")
    if not h:
        return ""
    if not h.startswith(("http://", "https://")):
        h = "http://" + h
    return h


def keenetic_validate(host: str, login: str, password: str, timeout: float = 5.0) -> bool:
    """Проверяет связку login/password против админки Keenetic по NDM-протоколу."""
    base = _normalize_host(host)
    if not base or not login or password is None:
        return False
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    realm = ""
    challenge = ""
    try:
        req = urllib.request.Request(base + "/auth", method="GET")
        with opener.open(req, timeout=timeout) as r:
            if r.status == 200:
                return True
            realm = r.headers.get("X-NDM-Realm", "") or ""
            challenge = r.headers.get("X-NDM-Challenge", "") or ""
    except urllib.error.HTTPError as e:
        if e.code != 401:
            return False
        realm = e.headers.get("X-NDM-Realm", "") or ""
        challenge = e.headers.get("X-NDM-Challenge", "") or ""
    except (urllib.error.URLError, OSError) as e:
        log.warning("auth: router unreachable %s: %s", base, e)
        return False
    if not realm or not challenge:
        return False
    md5 = hashlib.md5(f"{login}:{realm}:{password}".encode("utf-8")).hexdigest()
    sha = hashlib.sha256((challenge + md5).encode("utf-8")).hexdigest()
    body = json.dumps({"login": login, "password": sha}).encode("utf-8")
    try:
        req2 = urllib.request.Request(
            base + "/auth",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with opener.open(req2, timeout=timeout) as r2:
            return 200 <= r2.status < 300
    except urllib.error.HTTPError:
        return False
    except (urllib.error.URLError, OSError) as e:
        log.warning("auth: post failed %s: %s", base, e)
        return False


_lock = threading.Lock()
_sessions: dict[str, float] = {}
_TTL = 8 * 3600


def _gc_locked(now: float) -> None:
    expired = [t for t, exp in _sessions.items() if exp < now]
    for t in expired:
        _sessions.pop(t, None)


def issue_token(ttl: int = _TTL) -> str:
    now = time.time()
    token = secrets.token_urlsafe(32)
    with _lock:
        _gc_locked(now)
        _sessions[token] = now + ttl
    return token


def is_token_valid(token: str, ttl: int = _TTL) -> bool:
    if not token:
        return False
    now = time.time()
    with _lock:
        _gc_locked(now)
        exp = _sessions.get(token)
        if exp and exp >= now:
            _sessions[token] = now + ttl
            return True
    return False


def revoke_token(token: str) -> None:
    if not token:
        return
    with _lock:
        _sessions.pop(token, None)
