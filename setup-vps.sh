#!/bin/bash
# setup-vps.sh — turnkey: снос + установка WireGuard-сервера kssh-tunnel.
#
# Запуск (любой из вариантов):
#   curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/setup-vps.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/setup-vps.sh | sudo bash -s -- add <peer-name>
#
# Что делает (одной командой):
#   1) сносит предыдущий kssh-tunnel сервер (если был)
#   2) ставит сервер заново (apt install wireguard, ключи, wg0, kssh-tun)
#   3) если передан "add <name>" — сразу добавляет peer и печатает ENV-блок
#
# Что НЕ трогает: HydraRoute, любые ваши приложения, Docker, чужие правила
# iptables, apt-пакет wireguard (не делает remove).
set -e

REPO="${KSSH_REPO:-andrey271192/keenetic_ssh-web}"
BRANCH="${KSSH_BRANCH:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите через sudo." >&2
  exit 1
fi

echo "==> [1/3] Снос предыдущей установки kssh-tunnel сервера…"
curl -fsSL "$RAW/tunnel/server-uninstall.sh" | bash || true

echo
echo "==> [2/3] Установка сервера kssh-tunnel…"
curl -fsSL "$RAW/tunnel/server-install.sh" | bash

if [ "${1:-}" = "add" ] && [ -n "${2:-}" ]; then
  echo
  echo "==> [3/3] Добавление peer '$2'…"
  /usr/local/bin/kssh-tun add "$2"
else
  echo
  echo "==> [3/3] Сервер готов. Добавьте роутер командой:"
  echo "    sudo kssh-tun add <name>"
  echo "    (выдаст 5-строчный блок для копирования на роутер)"
fi
