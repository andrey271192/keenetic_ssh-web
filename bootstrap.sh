#!/bin/sh
# Одна команда с GitHub: скачивает архив main и запускает install.sh на роутере (Entware).
set -e

REPO="${KSSH_REPO:-andrey271192/keenetic_ssh-web}"
BRANCH="${KSSH_BRANCH:-main}"
ARCH="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
# Имя корня внутри tar: keenetic_ssh-web-main (последний сегмент REPO + -branch)
REPO_NAME="${REPO##*/}"
ROOT_DIR="${REPO_NAME}-${BRANCH}"

TMP="${TMPDIR:-/tmp}/kssh_bootstrap_$$"
mkdir -p "$TMP"
cd "$TMP"

echo "==> Скачивание ${ARCH}"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$ARCH" -o src.tgz
elif command -v wget >/dev/null 2>&1; then
  wget -qO src.tgz "$ARCH"
else
  echo "Нужны curl или wget (opkg install curl wget)" >&2
  exit 1
fi

echo "==> Распаковка"
tar xzf src.tgz
cd "$ROOT_DIR" || { echo "Нет каталога $ROOT_DIR в архиве" >&2; exit 1; }

chmod +x install.sh uninstall.sh run.sh 2>/dev/null || true
echo "==> Запуск install.sh"
./install.sh

cd /
rm -rf "$TMP"
