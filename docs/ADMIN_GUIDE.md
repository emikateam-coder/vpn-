# Руководство администратора

## 1. Добавление нового сервера

### 1.1. Арендуйте VPS

Любой провайдер (Aeza, Hetzner, DigitalOcean). Минимум: 1 vCPU, 1 GB RAM, Debian/Ubuntu.

### 1.2. Установите Marzban на новый сервер

```bash
ssh root@NEW_SERVER_IP
bash -c "$(curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban.sh)" @ install
```

### 1.3. Настройте Xray конфиг

Создайте `/var/lib/marzban/xray_config.json` с VLESS-Reality (замените ключи на новые):

```bash
# Сгенерируйте новые ключи
docker exec marzban_marzban_1 xray x25519
```

### 1.4. Добавьте сервер в бота

Отредактируйте `/opt/vpnbot/config.py` на ОСНОВНОМ сервере:

```python
SERVERS = {
    "de1": {
        "name": "Германия",
        "flag": "🇩🇪",
        "ip": "77.110.108.137",
        "inbound_tag": "VLESS_REALITY",
    },
    "nl1": {
        "name": "Нидерланды",
        "flag": "🇳🇱",
        "ip": "NEW_SERVER_IP",
        "inbound_tag": "VLESS_REALITY",
    },
}
```

Перезапустите бота:

```bash
systemctl restart vpnbot
```

### 1.5. Мультисерверный режим Marzban

Marzban поддерживает **ноды** -- один главный сервер + удалённые серверы.
Подробнее: https://gozargah.github.io/marzban/en/docs/nodes

---

## 2. Изменение тарифов

Отредактируйте `/opt/vpnbot/config.py`:

```python
PLANS = {
    "1m": {"name": "1 месяц", "days": 30, "gb": 0, "devices": "♾", "price": 149, "stars": 75},
    "3m": {"name": "3 месяца", "days": 90, "gb": 0, "devices": "♾", "price": 399, "stars": 200},
}
```

- `days` -- срок подписки в днях
- `gb` -- лимит трафика в ГБ (0 = безлимит)
- `price` -- цена в рублях (отображается)
- `stars` -- цена в Telegram Stars (используется при оплате)

Перезапустите: `systemctl restart vpnbot`

---

## 3. Управление промокодами

### Через бота (Админ-панель)

1. Откройте бота -> Админ-панель -> Добавить промокод
2. Введите код, срок, макс. использований

### Через файл напрямую

```bash
cat /var/lib/marzban/promo_codes.json
```

```json
{
  "FREE30": {"days": 30, "gb": 0, "max_uses": 10, "uses": 3},
  "VIP7": {"days": 7, "gb": 0, "max_uses": 100, "uses": 0}
}
```

---

## 4. Защита данных после работы агента

### 4.1. Смените SSH-пароль (ОБЯЗАТЕЛЬНО)

Пароль был в открытом доступе в чате.

```bash
ssh root@77.110.108.137
passwd
# Введите новый сложный пароль
```

### 4.2. Смените токен Telegram-бота

1. Откройте @BotFather в Telegram
2. Отправьте `/mybots` -> выберите бота -> API Token -> Revoke token
3. Скопируйте новый токен
4. На сервере:

```bash
nano /opt/vpnbot/.env
# Замените TELEGRAM_BOT_TOKEN=новый_токен
systemctl restart vpnbot
```

### 4.3. Смените пароль Marzban

```bash
docker exec -it marzban_marzban_1 marzban-cli admin update --username marzban_admin
# Следуйте инструкциям, введите новый пароль
```

Также обновите пароль в `.env` бота:

```bash
nano /opt/vpnbot/.env
# Замените MARZBAN_PASS=новый_пароль
systemctl restart vpnbot
```

### 4.4. Настройте SSH-ключи (рекомендуется)

```bash
# На вашем ПК
ssh-keygen -t ed25519 -C "my-key"
ssh-copy-id root@77.110.108.137

# На сервере -- отключите вход по паролю
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd
```

### 4.5. Смените SSH-порт

```bash
sed -i 's/^#*Port .*/Port 51822/' /etc/ssh/sshd_config
systemctl restart sshd
```

---

## 5. Полезные команды

```bash
# Статус бота
systemctl status vpnbot

# Логи бота
journalctl -u vpnbot -f

# Перезапуск бота
systemctl restart vpnbot

# Статус Marzban
marzban status

# Логи Marzban
marzban logs

# Перезапуск Marzban
marzban restart

# Панель Marzban (через nginx)
# http://77.110.108.137:8443/dashboard/

# Бэкап базы данных
cp /var/lib/marzban/db.sqlite3 ~/backup_$(date +%Y%m%d).db
```

---

## 6. Файлы на сервере

```
/opt/vpnbot/              -- Telegram бот
  .env                    -- секреты (токен, пароли)
  bot.py                  -- основной код бота
  config.py               -- тарифы, серверы
  marzban_api.py          -- API клиент Marzban
  promo.py                -- промокоды
  venv/                   -- Python окружение

/opt/marzban/             -- Marzban панель
  docker-compose.yml
  .env                    -- настройки Marzban

/var/lib/marzban/         -- данные Marzban
  db.sqlite3              -- база данных
  xray_config.json        -- конфиг Xray
  promo_codes.json        -- промокоды бота

/etc/nginx/sites-available/marzban -- nginx прокси
/etc/systemd/system/vpnbot.service -- сервис бота
```
