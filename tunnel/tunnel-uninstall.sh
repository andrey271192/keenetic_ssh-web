#!/bin/sh
# tunnel/tunnel-uninstall.sh — удаление WireGuard-клиента kssh-tunnel с роутера (Entware).
# Снимает ТОЛЬКО то, что поставил tunnel-install.sh:
#   - интерфейс wg0 (или WG_IF)
#   - /opt/etc/wireguard/<WG_IF>.conf
#   - init-скрипт /opt/etc/init.d/S50kssh-tunnel и rc.d-симлинк
#   - правила iptables/sysctl, добавленные туннелем (ACCEPT на wg0)
#
# Что НЕ трогает: пакет wireguard-tools, общие правила iptables, конфиги других
# WireGuard-интерфейсов (Keenetic NDM, HydraRoute и пр.), keenetic_ssh-web.
set -e

WG_IF="${WG_IF:-wg0}"
WG_DIR="/opt/etc/wireguard"
INIT="/opt/etc/init.d/S50kssh-tunnel"
RCD="/opt/etc/rc.d/S50kssh-tunnel"

echo "==> kssh-tunnel: удаление клиента ($WG_IF)"

# 1. Остановить интерфейс
if [ -x "$INIT" ]; then
  "$INIT" stop 2>/dev/null || true
fi
if ip link show "$WG_IF" >/dev/null 2>&1; then
  ip link del "$WG_IF" 2>/dev/null || true
fi

# 2. Снять правила, которые добавляли при старте туннеля
if command -v iptables >/dev/null 2>&1; then
  while iptables -C INPUT  -i "$WG_IF" -j ACCEPT 2>/dev/null; do
    iptables -D INPUT  -i "$WG_IF" -j ACCEPT 2>/dev/null || break
  done
  while iptables -C OUTPUT -o "$WG_IF" -j ACCEPT 2>/dev/null; do
    iptables -D OUTPUT -o "$WG_IF" -j ACCEPT 2>/dev/null || break
  done
fi

# 3. Удалить файлы туннеля (НЕ трогаем чужие WG-конфиги в этой папке)
rm -f "$WG_DIR/$WG_IF.conf"
rm -f "$RCD" "$INIT"
# Папку wireguard сносим только если она пуста (там могут лежать чужие конфиги)
rmdir "$WG_DIR" 2>/dev/null || true

echo
echo "============================================================"
echo "Готово. Удалены:"
echo "  $WG_DIR/$WG_IF.conf"
echo "  $INIT"
echo "  $RCD (если был)"
echo "  iptables ACCEPT для $WG_IF"
echo
echo "НЕ удалены (используются другими, не наша зона ответственности):"
echo "  пакет wireguard-tools (opkg)"
echo "  общие правила iptables / sysctl"
echo "  /opt/etc/wireguard/* кроме $WG_IF.conf"
echo "  keenetic_ssh-web (см. uninstall.sh в основном репо)"
echo "============================================================"
