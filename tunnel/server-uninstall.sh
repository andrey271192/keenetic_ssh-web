#!/bin/bash
# tunnel/server-uninstall.sh — удаление WireGuard-сервера kssh-tunnel с VPS.
# Снимает ТОЛЬКО то, что поставил server-install.sh:
#   - systemd-юнит wg-quick@wg0 (stop + disable)
#   - /etc/wireguard/wg0.conf, серверные ключи, peer-файлы, .kssh-tun.env
#   - /usr/local/bin/kssh-tun
#   - правила ufw, добавленные нами (открытие WG-порта и весь трафик на wg0)
#
# Что НЕ трогает: пакет wireguard / wireguard-tools (apt), iptables-правила
# других сервисов, любые ваши приложения и Docker.
set -e

WG_IF="${WG_IF:-wg0}"
WG_DIR="/etc/wireguard"
ENV_FILE="$WG_DIR/.kssh-tun.env"
WG_PORT="${WG_PORT:-51820}"

# Подхватить сохранённые значения, если есть
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите через sudo." >&2
  exit 1
fi

echo "==> kssh-tunnel server: удаление ($WG_IF, порт $WG_PORT)"

# 1. Остановить и выключить автозапуск
if command -v systemctl >/dev/null 2>&1; then
  systemctl stop    "wg-quick@${WG_IF}" 2>/dev/null || true
  systemctl disable "wg-quick@${WG_IF}" 2>/dev/null || true
fi

# 2. Снять интерфейс, если ещё жив
if ip link show "$WG_IF" >/dev/null 2>&1; then
  ip link del "$WG_IF" 2>/dev/null || true
fi

# 3. UFW: убрать только наши правила (если ufw активен)
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw delete allow "${WG_PORT}/udp"  >/dev/null 2>&1 || true
  ufw delete allow in  on "$WG_IF"   >/dev/null 2>&1 || true
  ufw delete allow out on "$WG_IF"   >/dev/null 2>&1 || true
fi

# 4. iptables: снять правило ACCEPT для wg0, которое мы вставляли
if command -v iptables >/dev/null 2>&1; then
  while iptables -C INPUT -i "$WG_IF" -j ACCEPT 2>/dev/null; do
    iptables -D INPUT -i "$WG_IF" -j ACCEPT 2>/dev/null || break
  done
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
  elif [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
  fi
fi

# 5. Файлы. Бережно: трогаем только наши.
rm -f "$WG_DIR/$WG_IF.conf"
rm -f "$WG_DIR/server_private.key" "$WG_DIR/server_public.key"
rm -f "$ENV_FILE"
if [ -d "$WG_DIR/peers" ]; then
  rm -f "$WG_DIR/peers/"*.peer 2>/dev/null || true
  rmdir "$WG_DIR/peers" 2>/dev/null || true
fi
# /etc/wireguard сносим только если он опустел (могут быть чужие WG-конфиги)
rmdir "$WG_DIR" 2>/dev/null || true

# 6. Утилита kssh-tun
rm -f /usr/local/bin/kssh-tun

echo
echo "============================================================"
echo "Готово. Удалены:"
echo "  $WG_DIR/$WG_IF.conf, server_private.key, server_public.key"
echo "  $WG_DIR/peers/*.peer, $ENV_FILE"
echo "  /usr/local/bin/kssh-tun"
echo "  systemd: wg-quick@${WG_IF} остановлен и отключён"
echo "  iptables / ufw: правила kssh-tunnel сняты"
echo
echo "НЕ удалены (общие, могут использоваться другим софтом):"
echo "  пакеты wireguard / wireguard-tools (apt remove — вручную, если не нужны)"
echo "  /etc/wireguard/* кроме файлов выше"
echo "  все остальные правила iptables / ufw"
echo "============================================================"
