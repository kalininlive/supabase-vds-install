#!/bin/bash
cd /opt/supabase-project

echo "Создание бэкапа..."
docker exec supabase-db pg_dump -U postgres -d postgres > backup_$(date +%F_%H-%M).sql

echo "✅ Бэкап сохранён"
