#!/bin/sh
# Установка keenetic_ssh-web на Keenetic (Entware) в /opt/share/keenetic_ssh-web
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
INST="${INSTALL_DIR:-/opt/share/keenetic_ssh-web}"
PY="${PYTHON:-python3}"

echo "==> Установка в $INST"

mkdir -p "$INST/data" /opt/var/run /opt/var/log 2>/dev/null || mkdir -p "$INST/data"

for f in app.py auth.py brand.py executor.py runner.py store.py requirements.txt run.sh; do
  cp -f "$ROOT/$f" "$INST/"
done
rm -rf "$INST/templates"
cp -a "$ROOT/templates" "$INST/"

if [ ! -f "$INST/data/store.json" ]; then
  cp -f "$ROOT/data/store.example.json" "$INST/data/store.json"
fi
if [ ! -f "$INST/.env" ]; then
  cp -f "$ROOT/.env.example" "$INST/.env"
  echo "!!! Создан $INST/.env — задайте WEB_PASSWORD и при необходимости ALLOWED_IPS"
fi

chmod +x "$INST/run.sh"

echo "==> Entware: python3 + venv"
if command -v opkg >/dev/null 2>&1; then
  opkg update
  opkg install python3 python3-pip python3-light python3-venv 2>/dev/null || opkg install python3 python3-pip 2>/dev/null || true
fi

cd "$INST"
if [ ! -x venv/bin/python3 ]; then
  "$PY" -m venv venv || { echo "Не удалось создать venv. Установите: opkg install python3-venv"; exit 1; }
fi
./venv/bin/pip install -q --upgrade pip
./venv/bin/pip install -q -r requirements.txt

INIT="/opt/etc/init.d/S99keenetic-ssh-web"
echo "==> Init-скрипт $INIT"
TMP_INIT="$(mktemp)"
cat > "$TMP_INIT" << 'INITEOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          keenetic-ssh-web
# Required-Start:    $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: keenetic_ssh-web (Flask+Waitress)
### END INIT INFO
DIR="@INST@"
PID="/opt/var/run/keenetic-ssh-web.pid"
case "$1" in
  start)
    if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
      echo "already running"
      exit 0
    fi
    [ -x "$DIR/venv/bin/python3" ] || { echo "no venv in $DIR"; exit 1; }
    cd "$DIR" || exit 1
    set -a
    [ -f .env ] && . ./.env
    set +a
    export PYTHONUNBUFFERED=1
    PORT="${PORT:-2001}"
    nohup "$DIR/venv/bin/python3" -m waitress --listen="0.0.0.0:$PORT" app:app \
      >>/opt/var/log/keenetic-ssh-web.log 2>&1 &
    echo $! > "$PID"
    echo "keenetic_ssh-web started pid=$(cat "$PID") port=$PORT"
    ;;
  stop)
    if [ -f "$PID" ]; then
      kill "$(cat "$PID")" 2>/dev/null || true
      rm -f "$PID"
    fi
    echo "stopped"
    ;;
  restart)
    "$0" stop
    sleep 1
    "$0" start
    ;;
  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
    ;;
esac
exit 0
INITEOF
sed "s|@INST@|$INST|g" "$TMP_INIT" > "$INIT"
rm -f "$TMP_INIT"
chmod +x "$INIT"

echo ""
echo "Готово. Дальше:"
echo "  1) nano $INST/.env   — WEB_PASSWORD, при желании ALLOWED_IPS и PORT"
echo "  2) $INIT start"
echo "  3) Браузер: http://IP_РОУТЕРА:2001 (или порт из $INST/.env → PORT)"
echo ""
echo "Автозапуск после перезагрузки (Entware):"
echo "  ln -sf $INIT /opt/etc/rc.d/S99keenetic-ssh-web   # если есть rc.d"
