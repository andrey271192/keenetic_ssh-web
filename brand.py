"""Полоска автора: GitHub, Boosty, Ozon (СБП), Telegram — как в keenetic-unified."""
from __future__ import annotations

import base64
import html


def _u(b64: str) -> str:
    return base64.b64decode(b64.encode("ascii")).decode("ascii")


_GH = _u("aHR0cHM6Ly9naXRodWIuY29tL2FuZHJleTI3MTE5Mg==")
_BZ = _u("aHR0cHM6Ly9ib29zdHkudG8vYW5kcmV5MjcvZG9uYXRl")
_OZ = _u(
    "aHR0cHM6Ly9maW5hbmNlLm96b24ucnUvYXBwcy9zYnAvb3pvbmJhbmtwYXkvMDE5ZGMyMDAtMmE1ZC03OTMxLWE2MTktNzgyZDI4NWY2Nzk4"
)

_WRAP = (
    "position:fixed;bottom:10px;left:12px;z-index:90;max-width:min(96vw,720px);"
    "font-size:11px;font-weight:600;letter-spacing:.02em;color:#86868b;opacity:.92;"
    "font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;"
    "display:flex;flex-wrap:wrap;align-items:center;gap:4px 10px;line-height:1.3"
)
_LBL = "color:#6e6e73;font-weight:500;margin-right:2px"
_A = (
    "color:#a1a1a6;text-decoration:none;border-bottom:1px solid rgba(255,255,255,.12)"
)
_DOT = "color:#86868b;user-select:none"


def brand_bar_html(telegram_username: str) -> str:
    u = (telegram_username or "Iot_andrey").lstrip("@")
    tg = f"https://t.me/{u}"
    safe_u = html.escape(u, quote=True)
    return (
        f'<div id="kssh-brand" lang="ru" style="{_WRAP}">'
        f'<span style="{_LBL}">автор:</span>'
        f'<a href="{_GH}" target="_blank" rel="noopener noreferrer" style="{_A}">GitHub</a>'
        f'<span style="{_DOT}">·</span>'
        f'<a href="{_BZ}" target="_blank" rel="noopener noreferrer" style="{_A}">Boosty</a>'
        f'<span style="{_DOT}">·</span>'
        f'<a href="{_OZ}" target="_blank" rel="noopener noreferrer" title="Поддержка проекта (Ozon Bank, СБП)" style="{_A}">'
        "Поддержка</a>"
        f'<span style="{_DOT}">·</span>'
        f'<a href="{html.escape(tg, quote=True)}" target="_blank" rel="noopener noreferrer" style="{_A}">'
        f"@{safe_u}</a></div>"
    )


def inject_brand(page_html: str, telegram_username: str) -> str:
    b = brand_bar_html(telegram_username)
    if "</body>" in page_html:
        return page_html.replace("</body>", f"{b}\n</body>", 1)
    return page_html + b
