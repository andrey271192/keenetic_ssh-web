#!/bin/sh
# tunnel/tunnel-install.sh — установка WireGuard-клиента на роутере (Entware).
# Запускается с роутера, принимает 4 ENV-переменные (выдаёт kssh-tun add на VPS):
#   VPS_ENDPOINT=<ip>:<port>   — публичный endpoint VPS, UDP
#   VPS_PUBKEY=<base64>        — публичный ключ сервера
#   CLIENT_IP=10.99.0.X        — IP роутера в туннельной подсети
#   CLIENT_PRIVKEY=<base64>    — приватный ключ роутера
# По желанию:
#   WG_IF=wg0                  — имя интерфейса (по умолчанию wg0)
#   WG_SUBNET=10.99.0.0/24     — какие IP маршрутизируются через туннель
#   WG_KEEPALIVE=25            — PersistentKeepalive в секундах
set -e

WG_IF="${WG_IF:-wg0}"
# Что маршрутизировать в туннель. По умолчанию только сам VPS (/32),
# чтобы не конфликтовать с возможными существующими маршрутами
# 10.99.0.0/24 на роутере (другие WG-интерфейсы Keenetic). Если нужен
# доступ к другим peer-ам в подсети — поставьте WG_SUBNET=10.99.0.0/24.
WG_SUBNET="${WG_SUBNET:-10.99.0.1/32}"
WG_KEEPALIVE="${WG_KEEPALIVE:-25}"
WG_DIR="/opt/etc/wireguard"
INIT="/opt/etc/init.d/S50kssh-tunnel"
NAT_TAG="kssh-tunnel:ndm81"

[ -z "$VPS_ENDPOINT" ] && { echo "VPS_ENDPOINT обязателен" >&2; exit 1; }
[ -z "$VPS_PUBKEY" ] && { echo "VPS_PUBKEY обязателен" >&2; exit 1; }
[ -z "$CLIENT_IP" ] && { echo "CLIENT_IP обязателен" >&2; exit 1; }
[ -z "$CLIENT_PRIVKEY" ] && { echo "CLIENT_PRIVKEY обязателен" >&2; exit 1; }

echo "==> WireGuard-клиент: $WG_IF $CLIENT_IP → $VPS_ENDPOINT"

# wireguard-tools (на Keenetic ядре уже есть модуль wireguard, нужны только утилиты)
if ! command -v wg >/dev/null 2>&1; then
  if command -v opkg >/dev/null 2>&1; then
    opkg update || echo "(opkg update: частичные ошибки источников — продолжаем)"
    opkg install wireguard-tools >/dev/null 2>&1 || true
  fi
fi
if ! command -v wg >/dev/null 2>&1; then
  echo "wg не найден. Установите вручную: opkg install wireguard-tools" >&2
  exit 1
fi

mkdir -p "$WG_DIR"
chmod 700 "$WG_DIR"

CONF="$WG_DIR/$WG_IF.conf"
umask 077
# Формат для `wg setconf` — без wg-quick полей (Address/DNS/Table/PostUp...).
# Address выставляем через `ip addr add` в init-скрипте.
cat > "$CONF" <<EOF
# kssh-tunnel client; адрес: $CLIENT_IP/24
[Interface]
PrivateKey = $CLIENT_PRIVKEY

[Peer]
PublicKey = $VPS_PUBKEY
Endpoint = $VPS_ENDPOINT
AllowedIPs = $WG_SUBNET
PersistentKeepalive = $WG_KEEPALIVE
EOF
chmod 600 "$CONF"

# Init-скрипт автозапуска
cat > "$INIT" <<INIEOF
#!/bin/sh
WG_IF="$WG_IF"
WG_DIR="$WG_DIR"
CONF="\$WG_DIR/\$WG_IF.conf"
ADDR="$CLIENT_IP/24"
SUBNET="$WG_SUBNET"
NAT_TAG="$NAT_TAG"

up() {
  ip link show "\$WG_IF" >/dev/null 2>&1 && ip link del "\$WG_IF" 2>/dev/null
  ip link add "\$WG_IF" type wireguard || { echo "ip link add не сработал — нет модуля wireguard в ядре?"; return 1; }
  if ! wg setconf "\$WG_IF" "\$CONF"; then
    echo "wg setconf вернул ошибку — проверьте \$CONF (формат: только PrivateKey + [Peer])"
    return 1
  fi
  ip addr add "\$ADDR" dev "\$WG_IF"
  ip link set "\$WG_IF" up
  ip route add "\$SUBNET" dev "\$WG_IF" 2>/dev/null || true
  # Keenetic: входящий трафик на сторонние интерфейсы режется stricht rp_filter +
  # нет ACCEPT для этих интерфейсов. Без этих двух строк handshake пройдёт, но
  # пинг и любые ответы VPS→роутер будут молча дропаться.
  sysctl -w net.ipv4.conf.all.rp_filter=2 >/dev/null 2>&1 || true
  sysctl -w "net.ipv4.conf.\$WG_IF.rp_filter=2" >/dev/null 2>&1 || true
  if command -v iptables >/dev/null 2>&1; then
    iptables -C INPUT  -i "\$WG_IF" -j ACCEPT 2>/dev/null || iptables -I INPUT  1 -i "\$WG_IF" -j ACCEPT
    iptables -C OUTPUT -o "\$WG_IF" -j ACCEPT 2>/dev/null || iptables -I OUTPUT 1 -o "\$WG_IF" -j ACCEPT
    # NDM/HTTP Proxy на Keenetic часто слушает на LAN-IP:81, но не на wg0:81.
    # Для доступа к /auth через туннель делаем DNAT wg0:81 → LAN_IP:81.
    LAN_IP=""
    for IF in br0 br-lan; do
      LAN_IP=\$(ip -4 -o addr show "\$IF" 2>/dev/null | awk '{print \$4}' | cut -d/ -f1 | head -n 1)
      [ -n "\$LAN_IP" ] && break
    done
    if [ -z "\$LAN_IP" ]; then
      LAN_IP=\$(ip -4 -o addr show 2>/dev/null | awk -v wg="\$WG_IF" '\$2!=wg && \$2!=\"lo\" {print \$4}' | cut -d/ -f1 | head -n 1)
    fi
    if [ -n "\$LAN_IP" ]; then
      iptables -t nat -C PREROUTING -i "\$WG_IF" -p tcp --dport 81 -m comment --comment "\$NAT_TAG" -j DNAT --to-destination "\$LAN_IP:81" 2>/dev/null || \
        iptables -t nat -I PREROUTING 1 -i "\$WG_IF" -p tcp --dport 81 -m comment --comment "\$NAT_TAG" -j DNAT --to-destination "\$LAN_IP:81" 2>/dev/null || true
    fi
  fi
  if ! wg show "\$WG_IF" | grep -q '^peer:'; then
    echo "ВНИМАНИЕ: peer не появился в \$WG_IF — handshake не состоится."
    echo "Проверьте \$CONF и перезапустите."
  fi
  echo "started \$WG_IF \$ADDR"
}
down() {
  ip link del "\$WG_IF" 2>/dev/null || true
  if command -v iptables >/dev/null 2>&1; then
    while iptables -C INPUT  -i "\$WG_IF" -j ACCEPT 2>/dev/null; do
      iptables -D INPUT  -i "\$WG_IF" -j ACCEPT 2>/dev/null || break
    done
    while iptables -C OUTPUT -o "\$WG_IF" -j ACCEPT 2>/dev/null; do
      iptables -D OUTPUT -o "\$WG_IF" -j ACCEPT 2>/dev/null || break
    done
    # удалить наши DNAT-правила (если были)
    while iptables -t nat -S PREROUTING 2>/dev/null | grep -q "\$NAT_TAG"; do
      RULE=\$(iptables -t nat -S PREROUTING | grep "\$NAT_TAG" | head -n 1 | sed 's/^-A /-D /')
      [ -n "\$RULE" ] && iptables -t nat \$RULE 2>/dev/null || break
    done
  fi
  echo "stopped \$WG_IF"
}

case "\$1" in
  start) up ;;
  stop) down ;;
  restart) down; sleep 1; up ;;
  status)
    ip -4 -o addr show "\$WG_IF" 2>/dev/null && wg show "\$WG_IF" 2>/dev/null || echo "(\$WG_IF не поднят)"
    ;;
  *) echo "usage: \$0 {start|stop|restart|status}"; exit 1 ;;
esac
INIEOF
chmod +x "$INIT"

# Поднять
"$INIT" restart || true

# Автозапуск через rc.d, если поддерживается
if [ -d /opt/etc/rc.d ] && [ ! -e /opt/etc/rc.d/S50kssh-tunnel ]; then
  ln -sf "$INIT" /opt/etc/rc.d/S50kssh-tunnel 2>/dev/null && \
    echo "==> Автозапуск: /opt/etc/rc.d/S50kssh-tunnel → $INIT"
fi

sleep 1
echo
echo "============================================================"
echo "Туннель $WG_IF поднят: $CLIENT_IP → $VPS_ENDPOINT"
echo "Конфиг:        $CONF"
echo "Init:          $INIT  {start|stop|restart|status}"
echo
ip -4 -o addr show "$WG_IF" 2>/dev/null | sed 's/^/  /'
wg show "$WG_IF" 2>/dev/null | sed 's/^/  /'
echo
VPS_IP="$(echo "$VPS_ENDPOINT" | cut -d: -f1)"
SERVER_TUN_IP="$(echo "$WG_SUBNET" | sed 's|0/24$|1|')"
echo "Проверка: ping -c 2 $SERVER_TUN_IP"
ping -c 2 -W 2 "$SERVER_TUN_IP" 2>/dev/null | sed 's/^/  /' || echo "  (ping не прошёл — проверьте VPS firewall: ufw allow 51820/udp)"
echo
echo "Теперь с VPS ($VPS_IP) роутер доступен по адресу: $CLIENT_IP"
echo "Например, веб-панель: http://$CLIENT_IP:2001"
echo "============================================================"
