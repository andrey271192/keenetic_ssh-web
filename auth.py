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
import ssl
import threading
import time
import urllib.error
import urllib.request

log = logging.getLogger("kssh.auth")

# У Keenetic админка на HTTPS обычно с самоподписанным сертификатом — отключаем проверку.
_SSL_CTX = ssl.create_default_context()
_SSL_CTX.check_hostname = False
_SSL_CTX.verify_mode = ssl.CERT_NONE


def _normalize_host(host: str) -> str:
    h = (host or "").strip().rstrip("/")
    if not h:
        return ""
    if not h.startswith(("http://", "https://")):
        h = "http://" + h
    return h


def keenetic_validate(host: str, login: str, password: str, timeout: float = 5.0) -> bool:
    """Проверяет связку login/password против одной админки Keenetic по NDM-протоколу.

    Логи пишут конкретную причину (unreachable / wrong code / no realm / bad password),
    чтобы при отказе была видна причина в /opt/var/log/keenetic-ssh-web.log.
    """
    base = _normalize_host(host)
    if not base or not login or password is None:
        return False
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(cj),
        urllib.request.HTTPSHandler(context=_SSL_CTX),
    )
    realm = ""
    challenge = ""
    try:
        req = urllib.request.Request(base + "/auth", method="GET")
        with opener.open(req, timeout=timeout) as r:
            if r.status == 200:
                log.info("auth: %s/auth вернул 200 без креденшелов — пускаем", base)
                return True
            realm = r.headers.get("X-NDM-Realm", "") or ""
            challenge = r.headers.get("X-NDM-Challenge", "") or ""
    except urllib.error.HTTPError as e:
        if e.code != 401:
            log.info("auth: GET %s/auth вернул HTTP %d (ожидали 401)", base, e.code)
            return False
        realm = e.headers.get("X-NDM-Realm", "") or ""
        challenge = e.headers.get("X-NDM-Challenge", "") or ""
    except (urllib.error.URLError, OSError) as e:
        log.warning("auth: %s недоступен: %s", base, e)
        return False
    if not realm or not challenge:
        log.warning("auth: %s/auth не вернул X-NDM-Realm/X-NDM-Challenge — это не Keenetic-админка?", base)
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
            if 200 <= r2.status < 300:
                log.info("auth: %s принял login=%s", base, login)
                return True
            log.info("auth: %s вернул HTTP %d", base, r2.status)
            return False
    except urllib.error.HTTPError as e:
        log.info("auth: %s POST HTTP %d (неверный логин/пароль?)", base, e.code)
        return False
    except (urllib.error.URLError, OSError) as e:
        log.warning("auth: %s POST не удался: %s", base, e)
        return False


def keenetic_validate_any(hosts: list[str], login: str, password: str, timeout: float = 5.0) -> bool:
    """Пробует каждый host из списка по очереди; True, если хотя бы один принял."""
    for h in hosts:
        if not h:
            continue
        try:
            if keenetic_validate(h, login, password, timeout=timeout):
                return True
        except Exception:
            log.exception("auth: ошибка при проверке %s", h)
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
