# keenetic_ssh-web

Локальный веб-интерфейс на **Keenetic + Entware**: список **shell-команд** на роутере (как «RouterSync», но вместо URL — **команда**), **расписание**, ручной запуск **всех** или **одной**, просмотр **stdout/stderr**. Сервис слушает порт **2001** (по умолчанию).

Репозиторий: [github.com/andrey271192/keenetic_ssh-web](https://github.com/andrey271192/keenetic_ssh-web)

---

<a id="white-ip-wan"></a>

## Важно: доступ только с «белых» / доверенных IP

Панель выполняет **произвольные команды в shell на самом роутере**. Размещайте её **только в доверенной сети** и **ограничьте WAN-доступ**.

- В `.env` задайте **`ALLOWED_IPS`** — список IP, с которых разрешены запросы (через запятую). Пустое значение = фильтр выключен (**не рекомендуется** на WAN).
- Дополнительно закройте порт **2001** на межсетевом экране Keenetic для всего интернета, кроме нужных адресов (как в справке Keenetic для облачного доступа: без прямого SSH с облака; здесь — **не публикуйте панель в открытый интернет** без allowlist).

**Пароль** `WEB_PASSWORD` обязателен: без него приложение не авторизует клиентов.

---

## Возможности

| | |
|---|---|
| **ВКЛ** | Команда участвует в ручном «Выполнить всё» и в одиночном запуске. |
| **Распис.** | Плюс участие в фоне по **интервалу** (минуты; **0** = только ручной режим). |
| **Вывод** | Кнопка «Вывод» раскрывает полный текст последнего запуска (stdout + stderr). |
| **Полоска автора** | GitHub, Boosty, Ozon (СБП), Telegram — внизу страницы (username из `.env`). |

Команды выполняются **на том же хосте**, где запущен Python (ваш Keenetic), с дополнением `PATH` для **Entware** (`/opt/bin` и т.д.).

---

## Требования

- Keenetic с **Entware**
- `python3`, желательно пакет **`python3-venv`** (`opkg install python3-venv`)
- Свободный порт **2001** (или другой в `.env`)

---

## Установка

Скопируйте каталог проекта на роутер (например, в `/tmp/keenetic_ssh-web`) или клонируйте репозиторий на ПК и скопируйте через SCP.

```sh
cd /path/to/keenetic_ssh-web
chmod +x install.sh uninstall.sh run.sh
./install.sh
```

Скрипт:

- копирует файлы в **`/opt/share/keenetic_ssh-web`**
- создаёт **`venv`**, ставит **Flask** и **Waitress**
- создаёт **`data/store.json`** и **`.env`** из примеров
- ставит **`/opt/etc/init.d/S99keenetic-ssh-web`**

Дальше:

```sh
nano /opt/share/keenetic_ssh-web/.env
# WEB_PASSWORD=...
# PORT=2001
# ALLOWED_IPS=192.168.1.100
# AUTHOR_TELEGRAM_USERNAME=Iot_andrey

/opt/etc/init.d/S99keenetic-ssh-web start
```

Откройте в браузере: `http://IP_РОУТЕРА:2001`

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

Для разработки на ПК:

```sh
python3 -m venv venv && ./venv/bin/pip install -r requirements.txt
export WEB_PASSWORD=test
./venv/bin/python app.py
# или: ./venv/bin/python -m waitress --listen=127.0.0.1:2001 app:app
```

---

## Удаление

```sh
cd /path/to/keenetic_ssh-web
chmod +x uninstall.sh
./uninstall.sh
```

Сохранить данные (`data/`, `.env`), но убрать сервис:

```sh
KEEP_DATA=1 ./uninstall.sh
```

---

## Переменные `.env`

| Переменная | Описание |
|------------|----------|
| `WEB_PASSWORD` | Пароль входа (**обязательно** сменить). |
| `PORT` | Порт HTTP (по умолчанию **2001**). |
| `CMD_TIMEOUT` | Таймаут одной команды, сек (по умолчанию **300**). |
| `AUTHOR_TELEGRAM_USERNAME` | Username для ссылки t.me внизу страницы. |
| `ALLOWED_IPS` | Список разрешённых IP клиентов через запятую; пусто = без фильтра (осторожно). |

---

## Безопасность

- Это **не песочница**: любая команда — с правами пользователя, от которого запущен процесс (часто **root** на Entware). Не вставляйте непроверенный текст.
- Не выставляйте порт в интернет без **пароля + allowlist** или VPN.
- Резервная копия: файл **`/opt/share/keenetic_ssh-web/data/store.json`**.

---

## Поддержка проекта

- **Boosty:** [boosty.to/andrey27/donate](https://boosty.to/andrey27/donate)
- **Ozon Bank (СБП):** [ссылка на оплату](https://finance.ozon.ru/apps/sbp/ozonbankpay/019dc200-2a5d-7931-a619-782d285f6798)
- **Telegram:** [@Iot_andrey](https://t.me/Iot_andrey)

Кнопка **Sponsor** на GitHub ведёт на варианты из `.github/FUNDING.yml`.

---

## Связанные проекты

- [keenetic-unified](https://github.com/andrey271192/keenetic-unified) — мониторинг и управление с **VPS** по SSH (нужен «белый» IP на WAN для SSH).
- В **keenetic_ssh-web** всё выполняется **локально на роутере**; сценарий доступа другой, но ограничение **ALLOWED_IPS** + файрвол по-прежнему рекомендуется.

---

## Лицензия

MIT
