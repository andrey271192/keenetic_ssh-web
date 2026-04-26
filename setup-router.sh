#!/bin/sh
# setup-router.sh — turnkey: снос + установка панели keenetic_ssh-web
# и (опционально) WireGuard-туннеля на роутере (Keenetic + Entware).
#
# На роутере (через SSH в Entware shell):
#
#   # Только панель (без туннеля):
#   curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/setup-router.sh | sh
#
#   # Панель + туннель — задайте 4 ENV-переменные перед запуском
#   # (их выдаёт `sudo kssh-tun add <name>` на VPS):
#   export VPS_ENDPOINT=212.118.42.105:51820
#   export VPS_PUBKEY='...'
#   export CLIENT_IP=10.99.0.X
#   export CLIENT_PRIVKEY='...'
#   curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/setup-router.sh | sh
#
# Что делает (одной командой):
#   1) сносит старую панель и старый клиент туннеля (если были)
#   2) ставит панель заново (порт 2001)
#   3) если ENV-переменные туннеля заданы — ставит туннель (wg0)
#
# Что НЕ трогает: HydraRoute Neo (hrneo, hrweb), XKeen, ваши кастомные репо,
# /opt/etc/opkg.conf, чужие WG-конфиги Keenetic, общие правила iptables.
set -e

REPO="${KSSH_REPO:-andrey271192/keenetic_ssh-web}"
BRANCH="${KSSH_BRANCH:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

WANT_TUNNEL=1
for v in VPS_ENDPOINT VPS_PUBKEY CLIENT_IP CLIENT_PRIVKEY; do
  eval "val=\"\${$v:-}\""
  if [ -z "$val" ]; then WANT_TUNNEL=0; fi
done

echo "==> [1/3] Снос старой установки (панель + туннель, если были)…"
curl -fsSL "$RAW/tunnel/tunnel-uninstall.sh" 2>/dev/null | sh || true
curl -fsSL "$RAW/uninstall.sh"               | sh || true

echo
echo "==> [2/3] Установка панели keenetic_ssh-web…"
curl -fsSL "$RAW/bootstrap.sh" | sh

echo
if [ "$WANT_TUNNEL" = "1" ]; then
  echo "==> [3/3] Установка туннеля ($CLIENT_IP → $VPS_ENDPOINT)…"
  curl -fsSL "$RAW/tunnel/tunnel-install.sh" | sh
else
  echo "==> [3/3] ENV-переменные туннеля не заданы — пропуск."
  echo "    Чтобы поставить туннель: задайте VPS_ENDPOINT/VPS_PUBKEY/CLIENT_IP/CLIENT_PRIVKEY"
  echo "    (их даёт 'sudo kssh-tun add <name>' на VPS) и запустите этот скрипт ещё раз."
fi

echo
echo "============================================================"
echo "Готово."
echo "Панель:  http://<LAN-IP>:2001  (логин/пароль — от веб-админки роутера)"
if [ "$WANT_TUNNEL" = "1" ]; then
  echo "Туннель: с VPS теперь доступно http://$CLIENT_IP:2001 и ssh root@$CLIENT_IP"
fi
echo "============================================================"
