#!/bin/sh
# Запуск через Waitress (рекомендуется на роутере). Поддерживает оба режима:
#   - venv:     $DIR/venv/bin/python3
#   - lib/:     /opt/bin/python3 + PYTHONPATH=$DIR/lib (если venv недоступен)
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR" || exit 1
set -a
[ -f .env ] && . ./.env
set +a
export PYTHONUNBUFFERED=1

if [ -x "$DIR/venv/bin/python3" ]; then
  PYBIN="$DIR/venv/bin/python3"
elif [ -d "$DIR/lib" ] && [ -x /opt/bin/python3 ]; then
  PYBIN="/opt/bin/python3"
  export PYTHONPATH="$DIR/lib:${PYTHONPATH:-}"
elif command -v python3 >/dev/null 2>&1; then
  PYBIN="$(command -v python3)"
else
  echo "Нет python3. Установите: opkg install python3 python3-pip" >&2
  exit 1
fi

exec "$PYBIN" -m waitress --listen="0.0.0.0:${PORT:-2001}" app:app
