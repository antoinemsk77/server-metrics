-- 01_schema.sql
-- создаём схему и основную таблицу для метрик

CREATE SCHEMA IF NOT EXISTS server;

CREATE TABLE IF NOT EXISTS server.metrics (
    id serial PRIMARY KEY,
    "timestamp" timestamptz NOT NULL DEFAULT now(),
    cpu_usage numeric,
    ram_total int,
    ram_used int,
    ram_free int,
    ram_available int,
    ram_cache int,
    ram_usage_percent real,
    swap_total int,
    swap_used int,
    swap_free int,
    swap_usage_percent real,
    disk_total_gb numeric,
    disk_used_gb numeric,
    disk_usage_percent real,
    net_rx_mb bigint,
    net_tx_mb bigint
)
PARTITION BY RANGE ("timestamp");

-- партиция по умолчанию
CREATE TABLE IF NOT EXISTS server.metrics_default
    PARTITION OF server.metrics DEFAULT;
