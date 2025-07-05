#!/bin/bash
cd /opt/supabase-project

echo "Создаём бэкап перед обновлением..."
docker exec supabase-db pg_dump -U postgres -d postgres > backup_$(date +%F_%H-%M).sql

echo "Останавливаем Supabase..."
docker compose down

echo "Обновляем образы..."
docker compose pull

echo "Запускаем Supabase..."
docker compose up -d

echo "✅ Обновление завершено"
