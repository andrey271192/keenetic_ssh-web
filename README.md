# keenetic_ssh-web

> Локальная веб-панель для **Keenetic + Entware**: набор **shell-команд** на роутере (как «RouterSync», но вместо URL — **команда**), **расписание**, ручной запуск **всех** или **одной** команды, просмотр **stdout/stderr**. Работает на самом роутере, слушает порт **2001**. Вход — по **логину и паролю от веб-админки роутера**.

Репозиторий: [github.com/andrey271192/keenetic_ssh-web](https://github.com/andrey271192/keenetic_ssh-web)

---

## Что внутри

| Что | Что делает |
|---|---|
| **Список команд** | `ВКЛ` / `Распис.` / `Название` / `Команда (shell)` / `Примечание` / `Последний запуск` / `Действия`. |
| **Расписание** | Один общий интервал в минутах. Запускаются строки с `ВКЛ` **и** `Распис.` (`0` — только ручной режим). |
| **«Выполнить всё»** | Запускает все строки с `ВКЛ` (независимо от `Распис.`). |
| **«Вывод»** | Раскрывает полный **stdout + stderr** последнего запуска. |
| **Авторизация** | По логину/паролю **веб-админки роутера** (NDM-протокол). Запасной мастер-пароль `WEB_PASSWORD` — опционально. |
| **Сессии** | Сессионный токен на 8 часов, лежит в `sessionStorage` браузера. |
| **Шапка автора и донат** | GitHub, Telegram, Boosty, Ozon (СБП) — наверху страницы. |
| **Лог** | `/opt/var/log/keenetic-ssh-web.log`. |

Команды выполняются **на том же хосте**, где работает Python (ваш Keenetic), с дополнением `PATH` для **Entware** (`/opt/bin`, `/opt/sbin` и т. д.).

---

<a id="white-ip-wan"></a>

## Важно: доступ только из доверенной сети

Панель выполняет **произвольные команды в shell на роутере**. Размещайте её **только в доверенной сети**, не публикуйте в открытый интернет.

- В `.env` укажите **`ALLOWED_IPS`** — список IP клиентов через запятую. Пустое значение = фильтр выключен (**не рекомендуется** на WAN).
- Закройте порт **`2001`** на межсетевом экране Keenetic для всего интернета, кроме нужных адресов.
- Вход в любом случае требует пароль (от админки роутера или `WEB_PASSWORD`).

---

## Требования

- Keenetic с **Entware**
- `python3`, желательно `python3-venv` (`opkg install python3-venv`)
- Свободный порт **2001** (или другой в `.env`)
- Доступная HTTP-админка Keenetic (по умолчанию `http://127.0.0.1` с самого роутера)

---

## Установка

### Одной командой с GitHub (на роутере, Entware)

Нужны **`curl`** или **`wget`** и **`tar`**. Скрипт скачает архив ветки `main`, распакует во временный каталог и выполнит `install.sh` (копирование в `/opt/share/keenetic_ssh-web`, venv, init).

```sh
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/bootstrap.sh | sh
```

Другая ветка или форк:

```sh
export KSSH_BRANCH=main
export KSSH_REPO=andrey271192/keenetic_ssh-web
curl -fsSL "https://raw.githubusercontent.com/${KSSH_REPO}/${KSSH_BRANCH}/bootstrap.sh" | sh
```

### Установка из уже скачанного каталога

```sh
cd /path/to/keenetic_ssh-web
chmod +x install.sh uninstall.sh run.sh bootstrap.sh
./install.sh
```

Скрипт:

- копирует файлы в **`/opt/share/keenetic_ssh-web`**
- ставит **Flask** и **Waitress**: предпочтительно в `venv/`; если модуль `venv` в Python отсутствует (типично для `aarch64-k3.10`), то — в локальный `lib/` через `pip install --target`
- создаёт **`data/store.json`** и **`.env`** из примеров
- устанавливает **`/opt/etc/init.d/S99keenetic-ssh-web`** (автоопределяет venv/lib режим)

### Первый запуск

```sh
vi /opt/share/keenetic_ssh-web/.env
# ROUTER_HOST=http://127.0.0.1   (если на роутере)
# ROUTER_LOGIN=admin
# WEB_PASSWORD=                  (запасной мастер-пароль; можно оставить пустым)
# PORT=2001
# ALLOWED_IPS=192.168.1.100      (по желанию)
# AUTHOR_TELEGRAM_USERNAME=Iot_andrey

/opt/etc/init.d/S99keenetic-ssh-web start
```

> На Entware из коробки нет `nano` — используйте `vi`. Если `opkg update` ругается на сторонний репо (например `hoaxisr.github.io`), это не страшно, установка продолжится.

Откройте в браузере: `http://IP_РОУТЕРА:2001` — введите **логин и пароль от веб-админки роутера**.

**Автозапуск** (если у вашей сборки Entware есть `rc.d`):

```sh
ln -sf /opt/etc/init.d/S99keenetic-ssh-web /opt/etc/rc.d/S99keenetic-ssh-web
```

Лог: `/opt/var/log/keenetic-ssh-web.log`

---

## Ручной запуск (без init)

```sh
cd /opt/share/keenetic_ssh-web
chmod +x run.sh
./run.sh
```

Для разработки на ПК (без роутера):

```sh
python3 -m venv venv && ./venv/bin/pip install -r requirements.txt
# на ПК `ROUTER_HOST` оставьте пустым и используйте мастер-пароль:
export ROUTER_HOST=
export WEB_PASSWORD=test
./venv/bin/python app.py
# или: ./venv/bin/python -m waitress --listen=127.0.0.1:2001 app:app
```

---

## Удаление

### С GitHub (скрипт самодостаточный)

```sh
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/uninstall.sh | sh
```

Сохранить каталог с данными (`.env`, `data/`), убрав только сервис:

```sh
curl -fsSL https://raw.githubusercontent.com/andrey271192/keenetic_ssh-web/main/uninstall.sh | env KEEP_DATA=1 sh
```

### Из каталога репозитория

```sh
cd /path/to/keenetic_ssh-web
chmod +x uninstall.sh
./uninstall.sh
# Сохранить данные:
KEEP_DATA=1 ./uninstall.sh
```

---

## Переменные `.env`

| Переменная | Описание | По умолчанию |
|---|---|---|
| `ROUTER_HOST` | HTTP-адрес админки Keenetic для проверки логина/пароля. На самом роутере — `http://127.0.0.1`. Пусто = выключить роутерную авторизацию. | `http://127.0.0.1` |
| `ROUTER_LOGIN` | Логин по умолчанию в форме входа. | `admin` |
| `ROUTER_TIMEOUT` | Таймаут запроса к `/auth` админки, сек. | `5` |
| `WEB_PASSWORD` | Запасной мастер-пароль. Если роутерная авторизация не сработала и пароль совпал — пустит. Можно оставить пустым. | пусто |
| `PORT` | Порт HTTP. | `2001` |
| `CMD_TIMEOUT` | Таймаут одной команды, сек. | `300` |
| `AUTHOR_TELEGRAM_USERNAME` | Username для ссылки `t.me` в шапке и снизу. | `Iot_andrey` |
| `ALLOWED_IPS` | Список разрешённых IP клиентов через запятую. Пусто = без фильтра. | пусто |

---

## Как устроена авторизация

1. Браузер → `POST /api/login` с `{login, password}`.
2. Сервер обращается по `ROUTER_HOST` к `/auth` админки Keenetic, читает `X-NDM-Realm` и `X-NDM-Challenge`, считает хеш `sha256(challenge + md5(login:realm:password))` и шлёт `POST /auth` на роутер.
3. Если роутер вернул `200 OK` — выдаём сессионный токен (`secrets.token_urlsafe(32)`), TTL **8 часов**, скользящее окно. Клиент кладёт его в `sessionStorage` и шлёт в заголовке `X-Session-Token`.
4. Если роутерная авторизация не сработала, но `WEB_PASSWORD` задан и совпал — тоже выдаём токен (мастер-пароль).

Никаких паролей в файлах не хранится. Токены живут в памяти процесса — рестарт сервиса = разлогин всех.

---

## Безопасность

- Это **не песочница**: команды выполняются с правами процесса (на Entware часто **root**). Не вставляйте непроверенный текст из чужих источников.
- Не выставляйте порт в интернет без `ALLOWED_IPS` или VPN.
- Резервная копия команд: `/opt/share/keenetic_ssh-web/data/store.json`.
- HTTP админки Keenetic на loopback (`http://127.0.0.1`) — это нормально для запросов с самого роутера. Между ПК и роутером используйте проводную/WiFi LAN или VPN.

---

## Поддержка проекта

- **Boosty:** [boosty.to/andrey27/donate](https://boosty.to/andrey27/donate)
- **Ozon Bank (СБП):** [ссылка на оплату](https://finance.ozon.ru/apps/sbp/ozonbankpay/019dc200-2a5d-7931-a619-782d285f6798)
- **Telegram:** [@Iot_andrey](https://t.me/Iot_andrey)
- **GitHub:** [andrey271192](https://github.com/andrey271192)

Кнопка **Sponsor** на GitHub ведёт на варианты из `.github/FUNDING.yml`.

---

## Связанные проекты

- [keenetic-unified](https://github.com/andrey271192/keenetic-unified) — мониторинг и управление с **VPS** по SSH (нужен «белый» IP на WAN для SSH).
- В **keenetic_ssh-web** всё работает **локально на роутере** — белый IP не нужен; ограничение `ALLOWED_IPS` + файрвол по-прежнему рекомендуется.

---

## Лицензия

MIT — см. [LICENSE](LICENSE).
