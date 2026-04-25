#!/bin/sh
# Удаление keenetic_ssh-web с роутера (Entware)
set -e
INST="${INSTALL_DIR:-/opt/share/keenetic_ssh-web}"
INIT="/opt/etc/init.d/S99keenetic-ssh-web"
RCD="/opt/etc/rc.d/S99keenetic-ssh-web"
PID="/opt/var/run/keenetic-ssh-web.pid"

[ -x "$INIT" ] && "$INIT" stop 2>/dev/null || true
rm -f "$RCD" "$INIT" "$PID"

if [ "${KEEP_DATA:-0}" = "1" ]; then
  echo "Каталог $INST сохранён (KEEP_DATA=1). Удалите вручную при необходимости."
  exit 0
fi

rm -rf "$INST"
echo "Удалено: $INST"
