# keenetic_ssh-web

> Локальная веб-панель для **Keenetic + Entware**: shell-команды на роутере, расписание, ручной запуск, просмотр stdout/stderr. Слушает порт **2001**. Авторизация — логин/пароль от веб-админки роутера.
>
> + опциональный модуль **`tunnel/`** — WireGuard VPS↔роутер, чтобы дотянуться до панели и SSH с **серого IP**, без проброса портов.

Репозиторий: [github.com/andrey271192/keenetic_ssh-web](https://github.com/andrey271192/keenetic_ssh-web)

---

## В репозитории два независимых пакета

| Пакет | Куда ставится | Зачем | Обязателен |
|---|---|---|---|
| **A. keenetic_ssh-web** | роутер (Entware) | веб-панель команд на 2001 | да |
| **B. tunnel** | VPS (Ubuntu) + роутер | WG-туннель для серого IP | нет, по желанию |

**Ставятся и удаляются отдельно**. Пакет B нужен только если у роутера серый IP и вы хотите управлять им из интернета через свой VPS. Если у вас белый IP / KeenDNS Cloud / достаточно LAN — ставьте только A.

> ⚠️ **Скрипты установки/удаления НЕ трогают** `hrneo`/`hrweb` (HydraRoute Neo), XKeen, Domain Hydra и любые ваши кастомные пакеты Entware. Не правят `/opt/etc/opkg.conf`, не сбрасывают чужие правила iptables, не ставят/удаляют пакеты, не относящиеся к данным двум пакетам.

---

## Сценарии и что ставить

| Сценарий | Доступ | Что ставить |
|---|---|---|
| Управляю только из дома (LAN) | `http://192.168.X.1:2001` | только **A** |
| Серый IP, нужен доступ из любой точки | `https://имя.домен` через ваш VPS | **A** + **B** + reverse-proxy на VPS |
| Белый IP / KeenDNS Cloud | проброс портов или KeenDNS на 2001 | только **A** (B не нужен) |

---

# A. keenetic_ssh-web — установка

## A.1. Требования

- Keenetic с **Entware** (`opkg` доступен)
- `python3` — установится автоматически из `bin.entware.net`
- Свободный порт **2001** (можно переопределить в `.env`)

## A.2. Установка одной командой (на роутере)

```sh
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/bootstrap.sh | sh
```

Что делает:
- скачивает архив ветки `main`, кладёт в `/opt/share/keenetic_ssh-web`
- ставит **только** `python3`, `python3-pip`, `python3-venv` (если их нет)
- кладёт init-скрипт `/opt/etc/init.d/S99keenetic-ssh-web` и rc.d-симлинк
- стартует сервис на порту 2001
- создаёт `.env` из примера и подставляет в `ROUTER_HOST` LAN-IP роутера

В конце выведет адрес панели: `http://<LAN-IP>:2001`. Логин/пароль — от веб-админки роутера.

> Другая ветка/форк: `KSSH_BRANCH=dev KSSH_REPO=user/repo curl … | sh`.

## A.3. Конфиг — `/opt/share/keenetic_ssh-web/.env`

| Переменная | Описание | По умолчанию |
|---|---|---|
| `ROUTER_HOST` | HTTP-адреса админки Keenetic для проверки логина (через запятую — пробуем по очереди). Установщик сам подставит LAN-IP. | `http://127.0.0.1` |
| `ROUTER_LOGIN` | Логин по умолчанию в форме входа | `admin` |
| `ROUTER_TIMEOUT` | Таймаут запроса к `/auth`, сек | `5` |
| `WEB_PASSWORD` | Запасной мастер-пароль (если админка недоступна) | пусто |
| `PORT` | HTTP-порт панели | `2001` |
| `CMD_TIMEOUT` | Таймаут одной shell-команды, сек | `300` |
| `ALLOWED_IPS` | Белый список IP клиентов (через запятую). Пусто = всех. | пусто |
| `AUTHOR_TELEGRAM_USERNAME` | username для ссылки в шапке | `Iot_andrey` |

После правки:
```sh
/opt/etc/init.d/S99keenetic-ssh-web restart
tail -f /opt/var/log/keenetic-ssh-web.log
```

> ⚠️ **Безопасность.** Панель выполняет произвольные shell-команды с правами процесса (на Entware часто root). Не открывайте порт 2001 в интернет напрямую. Используйте `ALLOWED_IPS` или туннель + reverse-proxy с HTTPS (см. пакет B).

## A.4. Управление сервисом

```sh
/opt/etc/init.d/S99keenetic-ssh-web start
/opt/etc/init.d/S99keenetic-ssh-web stop
/opt/etc/init.d/S99keenetic-ssh-web restart
tail -f /opt/var/log/keenetic-ssh-web.log
vi /opt/share/keenetic_ssh-web/.env
```

## A.5. Удаление keenetic_ssh-web

С GitHub:
```sh
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/uninstall.sh | sh
```

Сохранить `data/store.json` и `.env`:
```sh
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/uninstall.sh | env KEEP_DATA=1 sh
```

Удаляет ровно: `/opt/share/keenetic_ssh-web/`, `/opt/etc/init.d/S99keenetic-ssh-web`, `/opt/etc/rc.d/S99keenetic-ssh-web`, pid-файл.
**Не удаляет:** `python3`, `wireguard-tools`, `hrneo`, `hrweb`, любые другие пакеты Entware, лог `/opt/var/log/keenetic-ssh-web.log`.

---

# B. tunnel — установка (опционально, для серых IP)

```
[твой ПК] → https://router.домен (VPS, белый IP)
              │ Caddy/Nginx reverse-proxy
              ▼
         wg0 10.99.0.1 (VPS)
              ⇅  WireGuard, UDP/51820
         wg0 10.99.0.X (роутер за NAT провайдера)
              ▼
   127.0.0.1:2001  keenetic_ssh-web
   127.0.0.1:22    SSH
```

Туннель **инициирует роутер** наружу — серый IP / NAT провайдера не мешает.

## B.1. На VPS (Ubuntu) — один раз

```sh
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/tunnel/server-install.sh | sudo sh
```

Что делает:
- `apt install wireguard wireguard-tools curl`
- генерит серверные ключи (`/etc/wireguard/server_{private,public}.key`)
- создаёт `/etc/wireguard/wg0.conf` (UDP 51820, IP `10.99.0.1/24`)
- ставит утилиту `kssh-tun` в `/usr/local/bin/`
- открывает `51820/udp` и `wg0` в `ufw`/`iptables`, если активны
- запускает `wg-quick@wg0` и ставит на автозапуск

В конце печатает Endpoint и серверный PublicKey.

## B.2. На VPS — добавить роутер (peer)

```sh
sudo kssh-tun add router-name
```

Утилита:
- генерит ключи клиента, выделяет IP `10.99.0.X`
- сохраняет `/etc/wireguard/peers/<name>.peer`
- регенерирует `wg0.conf` и применяет (`systemctl restart wg-quick@wg0`)
- **выводит готовую команду для роутера** — четыре `export` + `curl … | sh`

Прочие команды:
```sh
sudo kssh-tun list                  # список peer-ов
sudo kssh-tun show <name>           # повторно вывести ENV-блок
sudo kssh-tun remove <name>         # удалить peer
sudo kssh-tun status                # wg show wg0
```

## B.3. На роутере — поднять клиент

Скопируйте блок из `kssh-tun add` и выполните на роутере (через SSH/Entware shell):

```sh
export VPS_ENDPOINT=212.118.42.105:51820
export VPS_PUBKEY='...'
export CLIENT_IP=10.99.0.X
export CLIENT_PRIVKEY='...'
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/tunnel/tunnel-install.sh | sh
```

Что делает:
- `opkg install wireguard-tools` (если нет)
- пишет `/opt/etc/wireguard/wg0.conf`
- поднимает интерфейс `wg0` с адресом `CLIENT_IP/24`
- ставит init-скрипт `/opt/etc/init.d/S50kssh-tunnel` + rc.d-симлинк
- **разрешает входящий трафик с туннеля** (`iptables -I INPUT -i wg0 -j ACCEPT` + `rp_filter=2`) — без этого Keenetic режет ответы из VPS, handshake пройдёт, а ping/HTTP — нет
- пингует `10.99.0.1` для проверки

После этого с VPS:
```sh
ping -c 3 10.99.0.X
ssh root@10.99.0.X            # если на роутере включён SSH
curl http://10.99.0.X:2001    # панель keenetic_ssh-web (если установлена)
```

## B.4. Reverse-proxy на VPS (доступ снаружи)

Caddyfile:
```
router.example.com {
    reverse_proxy 10.99.0.X:2001
}
```

Caddy выдаст HTTPS, и `https://router.example.com` отдаёт панель роутера. В `.env` keenetic_ssh-web укажите `ALLOWED_IPS=10.99.0.1` — только VPS будет иметь право заходить.

## B.5. Параметры (ENV)

`server-install.sh` (VPS):

| Переменная | По умолчанию | Описание |
|---|---|---|
| `WG_PORT` | `51820` | UDP-порт сервера |
| `WG_SUBNET_PREFIX` | `10.99.0` | Первые три октета `/24` |
| `WG_SERVER_LAST_OCTET` | `1` | Адрес сервера в туннеле |
| `KSSH_REPO`/`KSSH_BRANCH` | `andrey271192/keenetic_ssh-web` / `main` | Источник `kssh-tun` и `tunnel-install.sh` |

`tunnel-install.sh` (роутер):

| Переменная | Обязательная | Описание |
|---|---|---|
| `VPS_ENDPOINT` | да | `<публичный IP>:<порт>` |
| `VPS_PUBKEY` | да | PublicKey сервера |
| `CLIENT_IP` | да | IP роутера в туннеле |
| `CLIENT_PRIVKEY` | да | PrivateKey роутера (выдаёт `kssh-tun add`) |
| `WG_IF` | `wg0` | Имя интерфейса |
| `WG_SUBNET` | `10.99.0.1/32` | AllowedIPs клиента. По умолчанию только VPS, чтобы не ломать существующие WG-маршруты Keenetic. Поставьте `10.99.0.0/24` для peer-to-peer. |
| `WG_KEEPALIVE` | `25` | `PersistentKeepalive`, сек (нужен из-за NAT провайдера) |

## B.6. Удаление tunnel

### B.6.1. На роутере (только клиент)

```sh
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/tunnel/tunnel-uninstall.sh | sh
```

Удаляет: интерфейс `wg0`, `/opt/etc/wireguard/wg0.conf`, init-скрипт `S50kssh-tunnel`, rc.d-симлинк, наши правила `iptables ACCEPT для wg0`.
**Не удаляет:** `wireguard-tools`, общие правила iptables, чужие WG-конфиги, `keenetic_ssh-web`, HydraRoute Neo и др.

### B.6.2. На VPS (сервер)

```sh
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/tunnel/server-uninstall.sh | sudo sh
```

Удаляет: `wg-quick@wg0` (stop+disable), `/etc/wireguard/{wg0.conf,server_*.key,peers/,.kssh-tun.env}`, `/usr/local/bin/kssh-tun`, наши правила ufw/iptables.
**Не удаляет:** apt-пакеты `wireguard`/`wireguard-tools`, чужие правила ufw/iptables, ваши приложения и Docker.

Если потом захотите снести и сами apt-пакеты — вручную:
```sh
sudo apt remove --purge wireguard wireguard-tools
```

---

## Полный «с нуля» — пример

Допустим, на роутере уже стоит HydraRoute Neo, и его трогать **нельзя**. Хотим чистую установку обоих пакетов.

**1. На VPS:**
```sh
# (если что-то стояло раньше)
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/tunnel/server-uninstall.sh | sudo sh

# свежая установка сервера туннеля
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/tunnel/server-install.sh | sudo sh

# завести роутер
sudo kssh-tun add my-router
# → скопировать выданный 5-строчный блок
```

**2. На роутере:**
```sh
# (если что-то стояло раньше — оба пакета по отдельности)
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/tunnel/tunnel-uninstall.sh | sh
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/uninstall.sh | sh

# панель
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/bootstrap.sh | sh

# туннель — вставить выданный с VPS блок (4 export + curl)
export VPS_ENDPOINT=...
export VPS_PUBKEY='...'
export CLIENT_IP=10.99.0.X
export CLIENT_PRIVKEY='...'
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/tunnel/tunnel-install.sh | sh
```

**3. Проверка с VPS:**
```sh
ping -c 3 10.99.0.X
curl -I http://10.99.0.X:2001/
```

`hrneo`/`hrweb` (HydraRoute Neo) и любые ваши кастомные репозитории на обоих хостах остаются нетронутыми.

---

## Что лежит где

### keenetic_ssh-web (на роутере)
| Путь | |
|---|---|
| `/opt/share/keenetic_ssh-web/` | приложение, `.env`, `data/store.json`, venv/lib |
| `/opt/etc/init.d/S99keenetic-ssh-web` | init-скрипт |
| `/opt/etc/rc.d/S99keenetic-ssh-web` | автозапуск |
| `/opt/var/log/keenetic-ssh-web.log` | лог |
| `/opt/var/run/keenetic-ssh-web.pid` | pid |

### tunnel — клиент (на роутере)
| Путь | |
|---|---|
| `/opt/etc/wireguard/wg0.conf` | конфиг туннеля |
| `/opt/etc/init.d/S50kssh-tunnel` | init-скрипт |
| `/opt/etc/rc.d/S50kssh-tunnel` | автозапуск |

### tunnel — сервер (на VPS)
| Путь | |
|---|---|
| `/etc/wireguard/wg0.conf` | конфиг сервера (регенерируется `kssh-tun`) |
| `/etc/wireguard/server_{private,public}.key` | серверные ключи |
| `/etc/wireguard/peers/<name>.peer` | данные peer-а (имя/IP/ключи) |
| `/etc/wireguard/.kssh-tun.env` | параметры запуска |
| `/usr/local/bin/kssh-tun` | утилита |
| `systemctl status wg-quick@wg0` | сервис |

---

## Поддержка

- **GitHub:** [andrey271192](https://github.com/andrey271192)
- **Boosty:** [донат](https://boosty.to/andrey27/donate)
- **Telegram:** [@Iot_andrey](https://t.me/Iot_andrey)

## Лицензия

MIT — см. [LICENSE](LICENSE).
