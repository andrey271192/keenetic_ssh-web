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

echo "==> Entware: python3 + pip"
if command -v opkg >/dev/null 2>&1; then
  opkg update || echo "(opkg update: частичные ошибки источников — продолжаем)"
  # python3 + pip обязательны; python3-venv — желателен, но в некоторых сборках отсутствует
  opkg install python3 python3-pip >/dev/null 2>&1 || true
  opkg install python3-venv python3-light >/dev/null 2>&1 || true
fi

cd "$INST"

# 1) пробуем venv
USE_VENV=0
if [ -x venv/bin/python3 ]; then
  USE_VENV=1
elif "$PY" -m venv venv >/tmp/kssh-venv.log 2>&1; then
  USE_VENV=1
  echo "==> venv: $INST/venv"
else
  echo "==> venv недоступен (нет модуля venv в python3) — ставим зависимости в $INST/lib"
  rm -rf venv
fi

if [ "$USE_VENV" = "1" ]; then
  ./venv/bin/pip install -q --upgrade pip 2>/dev/null || true
  ./venv/bin/pip install -q -r requirements.txt
else
  # 2) фолбэк: pip install --target=lib (без venv, рабочий путь для старых Entware)
  if ! "$PY" -m pip --version >/dev/null 2>&1; then
    echo "ОШИБКА: ни venv, ни pip недоступны. Установите вручную: opkg install python3-pip"
    exit 1
  fi
  rm -rf lib
  mkdir -p lib
  "$PY" -m pip install -q --target=lib --upgrade pip 2>/dev/null || true
  "$PY" -m pip install -q --target=lib -r requirements.txt
fi

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
    cd "$DIR" || exit 1
    if [ -x "$DIR/venv/bin/python3" ]; then
      PYBIN="$DIR/venv/bin/python3"
    elif [ -d "$DIR/lib" ] && [ -x /opt/bin/python3 ]; then
      PYBIN="/opt/bin/python3"
      export PYTHONPATH="$DIR/lib:${PYTHONPATH:-}"
    else
      echo "Нет ни $DIR/venv, ни $DIR/lib — установите заново: $DIR/install.sh"
      exit 1
    fi
    set -a
    [ -f .env ] && . ./.env
    set +a
    export PYTHONUNBUFFERED=1
    PORT="${PORT:-2001}"
    nohup "$PYBIN" -m waitress --listen="0.0.0.0:$PORT" app:app \
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
echo "============================================================"
echo "Готово. Установлено в: $INST"
echo "Init-скрипт:           $INIT"
echo ""
echo "Дальше:"
echo "  1) (по желанию) vi $INST/.env"
echo "       ROUTER_HOST=http://127.0.0.1   ROUTER_LOGIN=admin"
echo "       WEB_PASSWORD=...               PORT=2001"
echo "       ALLOWED_IPS=192.168.1.100"
echo "  2) $INIT start"
echo "  3) Браузер: http://IP_РОУТЕРА:2001"
echo "     Логин/пароль — от веб-админки роутера (Keenetic)."
echo ""
echo "Автозапуск после перезагрузки (если есть rc.d):"
echo "  ln -sf $INIT /opt/etc/rc.d/S99keenetic-ssh-web"
echo "============================================================"
