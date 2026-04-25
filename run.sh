#!/bin/sh
# Запуск через Waitress (рекомендуется на роутере)
cd "$(dirname "$0")" || exit 1
set -a
[ -f .env ] && . ./.env
set +a
export PYTHONUNBUFFERED=1
exec /opt/bin/python3 -m waitress --listen="0.0.0.0:${PORT:-2001}" app:app
