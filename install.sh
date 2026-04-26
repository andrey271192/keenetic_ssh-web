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
  # Подставляем в свежий .env обнаруженный LAN-IP роутера в ROUTER_HOST,
  # чтобы клиент не оставался на одном лишь loopback (часто закрыт у Keenetic).
  LAN_IP_GUESS="$(
    ip -4 -o addr show 2>/dev/null \
      | awk '$4 ~ /^(192\.168|10|172\.(1[6-9]|2[0-9]|3[01]))\..*\.1\// {sub("/.*","",$4); print $4; exit}'
  )"
  if [ -n "$LAN_IP_GUESS" ]; then
    DEFAULT_HOSTS="http://${LAN_IP_GUESS},https://${LAN_IP_GUESS},http://${LAN_IP_GUESS}:81,http://my.keenetic.net,https://my.keenetic.net,http://127.0.0.1"
    sed -i "s|^ROUTER_HOST=.*|ROUTER_HOST=${DEFAULT_HOSTS}|" "$INST/.env" 2>/dev/null || true
    echo "==> .env: ROUTER_HOST подставлен LAN-IP $LAN_IP_GUESS (HTTP/HTTPS, можно изменить в $INST/.env)"
  fi
  echo "!!! Создан $INST/.env — при необходимости задайте WEB_PASSWORD/ALLOWED_IPS"
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
  "$PY" -m pip install -q --upgrade --target=lib pip 2>/dev/null || true
  "$PY" -m pip install -q --upgrade --target=lib -r requirements.txt
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
    LOG="/opt/var/log/keenetic-ssh-web.log"
    # Запуск в фоне без nohup (его в BusyBox этой сборки нет).
    # Предпочитаем setsid (новая сессия), иначе сабшелл с trap '' HUP.
    if command -v setsid >/dev/null 2>&1; then
      setsid "$PYBIN" -m waitress --listen="0.0.0.0:$PORT" app:app \
        </dev/null >>"$LOG" 2>&1 &
    elif command -v nohup >/dev/null 2>&1; then
      nohup "$PYBIN" -m waitress --listen="0.0.0.0:$PORT" app:app \
        >>"$LOG" 2>&1 &
    else
      ( trap '' HUP; exec "$PYBIN" -m waitress --listen="0.0.0.0:$PORT" app:app \
        </dev/null >>"$LOG" 2>&1 ) &
    fi
    echo $! > "$PID"
    sleep 1
    if kill -0 "$(cat "$PID")" 2>/dev/null; then
      echo "keenetic_ssh-web started pid=$(cat "$PID") port=$PORT"
    else
      rm -f "$PID"
      echo "ОШИБКА запуска. Лог: tail -n 30 $LOG"
      exit 1
    fi
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

# Автозапуск демона (можно отключить: NO_START=1 ./install.sh)
if [ "${NO_START:-0}" != "1" ]; then
  echo "==> Запуск $INIT"
  "$INIT" restart || echo "(не удалось стартовать; посмотрите лог: tail /opt/var/log/keenetic-ssh-web.log)"
fi

# Автозапуск после перезагрузки, если в Entware есть rc.d
if [ -d /opt/etc/rc.d ] && [ ! -e /opt/etc/rc.d/S99keenetic-ssh-web ]; then
  ln -sf "$INIT" /opt/etc/rc.d/S99keenetic-ssh-web 2>/dev/null && \
    echo "==> Автозапуск: /opt/etc/rc.d/S99keenetic-ssh-web → $INIT"
fi

# Узнаём LAN-IP роутера для подсказки в браузер: ищем 192.168.x.1 / 10.x.x.1
ROUTER_IP="$(
  ip -4 -o addr show 2>/dev/null \
    | awk '$4 ~ /^(192\.168|10|172\.(1[6-9]|2[0-9]|3[01]))\..*\.1\// {sub("/.*","",$4); print $4; exit}'
)"
if [ -z "$ROUTER_IP" ]; then
  ROUTER_IP="$(ifconfig 2>/dev/null \
    | awk '/inet (addr:)?(192\.168|10\.|172\.)/ {for(i=1;i<=NF;i++) if($i ~ /^(addr:)?(192\.168|10\.|172\.)/){gsub("addr:","",$i); if($i ~ /\.1$/){print $i; exit}}}')"
fi
[ -z "$ROUTER_IP" ] && ROUTER_IP="IP_РОУТЕРА"

echo ""
echo "============================================================"
echo "Готово. Установлено в: $INST"
echo "Init-скрипт:           $INIT"
echo "Лог:                   /opt/var/log/keenetic-ssh-web.log"
echo ""
echo "Откройте в браузере: http://${ROUTER_IP}:2001"
echo "Логин/пароль — как у веб-админки роутера (Keenetic)."
echo ""
echo "Полезные команды:"
echo "  $INIT {start|stop|restart}"
echo "  vi $INST/.env       (правка конфигурации)"
echo "  tail -f /opt/var/log/keenetic-ssh-web.log"
echo "============================================================"
