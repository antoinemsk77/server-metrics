# server-metrics

Агент в Docker собирает метрики сервера каждую секунду и пишет в PostgreSQL (схема `server`).  
Планировщик обновляет материализованные витрины и управляет партициями.

---

## Быстрый старт

```bash
cp .env.example .env   # заполните креды к вашей БД
docker compose up -d --build
```

---

## Развёртывание базы данных

В репозитории есть SQL-скрипты для создания схемы, таблиц, функций и витрин.

```bash
# создать схему и таблицу metrics
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f db/01_schema.sql

# функции для партиционирования
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f db/02_partitions.sql

# представления и материализованные витрины
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f db/03_views.sql
```

---

## Проверка работы

```sql
-- лаг вставок (должен быть секунды)
SELECT now() - max("timestamp") AS insert_lag FROM server.metrics;

-- последние 10 минут по минутам
SELECT *
FROM server.metrics_minutely
WHERE minute_ts >= now() - interval '10 minutes'
ORDER BY minute_ts DESC;
```

---

## Структура репозитория

```
server-metrics/
├─ agent/                  # Python-агент
├─ scripts/                # shell-скрипты для cron
├─ cron/                   # расписание cron
├─ db/                     # SQL-скрипты для БД
│   ├─ 01_schema.sql
│   ├─ 02_partitions.sql
│   └─ 03_views.sql
├─ docker-compose.yml
├─ .env.example
└─ README.md
```

---

## Лицензия

MIT License

Copyright (c) 2025 Antoine Melnikov

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction...
