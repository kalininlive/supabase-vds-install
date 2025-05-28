# Скрипт автоустановки Supabase на VDS с нуля

## Автор

**WebSansay** — Telegram: [@websansay](https://t.me/websansay)

---

## Шаг 1: Регистрация и покупка VDS на Beget

1. Перейди по реферальной ссылке: [https://beget.com/p801417/ru/cloud](https://beget.com/p801417/ru/cloud)
2. Выбери тариф с **минимум 2 GB RAM**.
3. В настройках укажи:

   * ОС: **Ubuntu 22.04**
   * Задай свой **пароль root**
   * Доп. параметр: **имя сервера** (например: `supabase-vds`)

---

## Шаг 2: Домен + A-запись

1. Регистрируй домен (если ещё не существует)
2. В DNS-настройках сделай A-запись:

   * **A запись:** `@` → **IP-адрес сервера**

Пример: `mydomain.ru` → `45.91.8.142`

---

## Шаг 3: Установка Termius и подключение к серверу

1. Скачай [Termius](https://termius.com/) (macOS, Windows, Linux)
2. Введи в профиле:

   * **IP-адрес сервера**
   * **Username:** `root`
   * **Password:** тот, что задавал на Beget

---

## Шаг 4: Установка Supabase

1. Введи команду:

```bash
bash <(curl -s https://raw.githubusercontent.com/websansay/supabase-vds-install/main/install.sh)
```

2. Скрипт:

   * Установит необходимые компоненты:

     * `curl`, `docker`, `docker-compose`, `nginx`, `certbot`, `apache2-utils`
     * Полезные утилиты: `git`, `jq`, `htop`, `net-tools`, `ufw`
   * Настроит Supabase в `/opt/supabase`
   * Запросит логин/пароль для защиты веб-доступа
   * Настроит `.htpasswd` и `nginx` с SSL
   * Запустит Supabase и привяжет домен

---

## В комплект установки входит

* Supabase (self-hosted) через Docker
* Nginx с HTTPS и защитой по логину/паролю (basic auth)
* Автоматическое получение SSL-сертификата (Let's Encrypt)
* Полезные утилиты: `git`, `jq`, `htop`, `net-tools`, `ufw`
* Хранение всех данных в `/opt/supabase` (включая базы, конфиги и volumes)

---

## Как безопасно обновлять Supabase

Создай файл `update.sh`:

```bash
#!/bin/bash
cd /opt/supabase

echo "Создаём бэкап перед обновлением..."
docker exec supabase-db pg_dump -U postgres -d postgres > backup_$(date +%F_%H-%M).sql

echo "Останавливаем Supabase..."
docker compose down

echo "Обновляем образы..."
docker compose pull

echo "Запускаем Supabase..."
docker compose up -d

echo "✅ Обновление завершено"
```

Запуск:

```bash
bash update.sh
```

---

## Как сделать резервную копию Supabase вручную

Создай файл `backup.sh`:

```bash
#!/bin/bash
cd /opt/supabase

echo "Создание бэкапа..."
docker exec supabase-db pg_dump -U postgres -d postgres > backup_$(date +%F_%H-%M).sql

echo "✅ Бэкап сохранён"
```

Запуск:

```bash
bash backup.sh
```

Можно настроить `cron`, чтобы делать бэкап каждый день в 2:00:

```bash
0 2 * * * /bin/bash /opt/supabase/backup.sh
```

---

## Готово!

Теперь Supabase запущен на твоём сервере, привязан к домену и хранит данные локально. Тюнинг и интеграцию с n8n рассмотрим в следующих инструкциях.
