# Supabase VDS Install

Автоустановка Supabase на VDS с доменом, Nginx, SSL и авторизацией.

**Автор:** [@websansay](https://t.me/websansay)

---

## 🖥️ Шаг 1: Регистрация сервера на Beget

1. Перейди по ссылке: [https://beget.com/p801417/ru/cloud](https://beget.com/p801417/ru/cloud)
2. Выбери тариф от **2 GB RAM**
3. Настрой:

   * Операционная система: `Ubuntu 22.04`
   * Придумай и задай пароль root
   * Задай имя сервера (например `supabase-vds`)

---

## 🌐 Шаг 2: Подключение домена

1. Зарегистрируй домен (если его ещё нет)
2. В DNS-записях создай `A`-запись:

@@ -44,81 +42,81 @@
---

## ⚙️ Шаг 4: Установка Supabase

Введи в терминале одну команду:

```bash
bash <(curl -s https://raw.githubusercontent.com/kalininlive/supabase-vds-install/main/install.sh)
```

Скрипт установит:

* Docker и docker-compose
* Supabase self-hosted (через Supabase CLI и `supabase start`)
* Nginx с SSL (Let's Encrypt) и Basic Auth (логин/пароль для доступа к Supabase Studio)
* Запросит домен и подставит его в nginx
* Полезные утилиты: `git`, `jq`, `htop`, `net-tools`, `ufw`, `unzip`

---

## ✅ Что входит в установку

* 📦 Supabase (PostgreSQL, API, Studio, Auth, Storage и прочие сервисы)
* 🔒 Basic Auth (защита по логину/паролю для Supabase Studio)
* 🌐 HTTPS с автоматическим сертификатом от Let's Encrypt
* 📂 Хранение данных в `/opt/supabase-project`

---

## 🔄 Обновление Supabase

Запусти обновление командой:

```bash
bash <(curl -s https://raw.githubusercontent.com/kalininlive/supabase-vds-install/main/update.sh)
```

### Что делает `update.sh`:

* Создаёт резервную копию перед обновлением
* Перезапускает Supabase с новыми Docker образами

---

## 💾 Резервная копия базы данных

Для ручного бэкапа:

```bash
bash <(curl -s https://raw.githubusercontent.com/kalininlive/supabase-vds-install/main/backup.sh)
```

Можно добавить автоматический бэкап в `cron`:

```cron
0 2 * * * /bin/bash /opt/supabase-project/backup.sh
```

---

## 📦 Быстрый запуск скриптов

```bash
# Установка Supabase
bash <(curl -s https://raw.githubusercontent.com/kalininlive/supabase-vds-install/main/install.sh)

# Безопасное обновление Supabase
bash <(curl -s https://raw.githubusercontent.com/kalininlive/supabase-vds-install/main/update.sh)

# Резервное копирование базы данных
bash <(curl -s https://raw.githubusercontent.com/kalininlive/supabase-vds-install/main/backup.sh)
```

---

## 📁 Скрипты в репозитории

| Скрипт                                                                                   | Назначение           |
| ---------------------------------------------------------------------------------------- | -------------------- |
| [`install.sh`](https://github.com/kalininlive/supabase-vds-install/blob/main/install.sh) | Установка Supabase   |
| [`update.sh`](https://github.com/kalininlive/supabase-vds-install/blob/main/update.sh)   | Обновление с бэкапом |
