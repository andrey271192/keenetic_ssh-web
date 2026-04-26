#!/bin/bash
# tunnel/server-install.sh — установка WireGuard-сервера на Ubuntu VPS.
# Поднимает wg0 (UDP 51820, подсеть 10.99.0.0/24) и ставит утилиту kssh-tun
# для добавления/удаления клиентов с генерацией ENV-блока для роутера.
set -e

WG_PORT="${WG_PORT:-51820}"
WG_SUBNET_PREFIX="${WG_SUBNET_PREFIX:-10.99.0}"
WG_SERVER_LAST_OCTET="${WG_SERVER_LAST_OCTET:-1}"
WG_SERVER_IP="${WG_SUBNET_PREFIX}.${WG_SERVER_LAST_OCTET}"
WG_SERVER_CIDR="${WG_SERVER_IP}/24"
WG_DIR="/etc/wireguard"
WG_IF="wg0"
KSSH_REPO="${KSSH_REPO:-andrey271192/keenetic_ssh-web}"
KSSH_BRANCH="${KSSH_BRANCH:-main}"
RAW="https://raw.githubusercontent.com/${KSSH_REPO}/${KSSH_BRANCH}/tunnel"

if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите через sudo." >&2
  exit 1
fi

echo "==> apt: wireguard wireguard-tools curl"
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wireguard wireguard-tools iproute2 curl

mkdir -p "$WG_DIR" "$WG_DIR/peers"
chmod 700 "$WG_DIR"

# Серверные ключи (один раз)
if [ ! -s "$WG_DIR/server_private.key" ] || [ ! -s "$WG_DIR/server_public.key" ]; then
  echo "==> Генерация ключей сервера"
  umask 077
  wg genkey | tee "$WG_DIR/server_private.key" | wg pubkey > "$WG_DIR/server_public.key"
fi

# Сохраняем параметры запуска (используется kssh-tun для регенерации конфига)
cat > "$WG_DIR/.kssh-tun.env" <<EOF
WG_PORT=$WG_PORT
WG_IF=$WG_IF
WG_SUBNET_PREFIX=$WG_SUBNET_PREFIX
WG_SERVER_IP=$WG_SERVER_IP
WG_SERVER_CIDR=$WG_SERVER_CIDR
WG_DIR=$WG_DIR
KSSH_REPO=$KSSH_REPO
KSSH_BRANCH=$KSSH_BRANCH
EOF
chmod 600 "$WG_DIR/.kssh-tun.env"

# Установка утилиты kssh-tun (peer management)
echo "==> Установка /usr/local/bin/kssh-tun"
if [ -f "$(dirname "$0")/kssh-tun" ]; then
  install -m 755 "$(dirname "$0")/kssh-tun" /usr/local/bin/kssh-tun
else
  curl -fsSL "$RAW/kssh-tun" -o /usr/local/bin/kssh-tun
  chmod 755 /usr/local/bin/kssh-tun
fi

# Сборка wg0.conf из server-ключа + всех peer-файлов
/usr/local/bin/kssh-tun _regen

# Включить и запустить
systemctl enable "wg-quick@${WG_IF}" >/dev/null 2>&1 || true
systemctl restart "wg-quick@${WG_IF}"

# UFW: открываем UDP-порт WG и ВЕСЬ трафик внутри туннеля (на самом wg0).
# Без второго правила handshake пройдёт, а ping/HTTP внутри wg0 будут глохнуть.
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "${WG_PORT}/udp" >/dev/null 2>&1 || true
  ufw allow in on "$WG_IF" >/dev/null 2>&1 || true
  ufw allow out on "$WG_IF" >/dev/null 2>&1 || true
fi

PUB_IP="$(curl -s4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
SERVER_PUB="$(cat "$WG_DIR/server_public.key")"

echo
echo "============================================================"
echo "WireGuard сервер готов."
echo "  Endpoint:    ${PUB_IP}:${WG_PORT}/udp"
echo "  PublicKey:   ${SERVER_PUB}"
echo "  Server IP:   ${WG_SERVER_IP}"
echo
echo "Добавление клиента (peer):"
echo "  sudo kssh-tun add <name>      # выдаст ENV-блок для роутера"
echo "  sudo kssh-tun list"
echo "  sudo kssh-tun show <name>"
echo "  sudo kssh-tun remove <name>"
echo "============================================================"
