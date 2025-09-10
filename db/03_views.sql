-- 03_views.sql
-- представления и материализованные витрины

-- enriched view
CREATE OR REPLACE VIEW server.v_metrics_enriched AS
WITH s AS (
  SELECT m.*,
         LAG(m.net_rx_mb) OVER (ORDER BY m."timestamp") AS prev_rx_mb,
         LAG(m.net_tx_mb) OVER (ORDER BY m."timestamp") AS prev_tx_mb,
         LAG(m."timestamp") OVER (ORDER BY m."timestamp") AS prev_ts
  FROM server.metrics m
),
d AS (
  SELECT s.*,
         EXTRACT(EPOCH FROM (s."timestamp" - s.prev_ts))::int AS dt_sec,
         CASE WHEN s.prev_rx_mb IS NULL OR EXTRACT(EPOCH FROM (s."timestamp" - s.prev_ts)) <= 0 OR s.net_rx_mb < s.prev_rx_mb
              THEN NULL ELSE (s.net_rx_mb - s.prev_rx_mb) END AS rx_delta_mb,
         CASE WHEN s.prev_tx_mb IS NULL OR EXTRACT(EPOCH FROM (s."timestamp" - s.prev_ts)) <= 0 OR s.net_tx_mb < s.prev_tx_mb
              THEN NULL ELSE (s.net_tx_mb - s.prev_tx_mb) END AS tx_delta_mb
  FROM s
)
SELECT d.id,
       d."timestamp",
       d.cpu_usage,
       d.ram_total, d.ram_used, d.ram_free, d.ram_available, d.ram_cache,
       COALESCE(d.ram_usage_percent, CASE WHEN d.ram_total > 0 THEN ROUND((d.ram_used::numeric / d.ram_total::numeric) * 100, 1) END)::real AS ram_usage_percent,
       d.swap_total, d.swap_used, d.swap_free,
       COALESCE(d.swap_usage_percent, CASE WHEN d.swap_total > 0 THEN ROUND((d.swap_used::numeric / d.swap_total::numeric) * 100, 1) END)::real AS swap_usage_percent,
       d.disk_total_gb, d.disk_used_gb,
       COALESCE(d.disk_usage_percent, CASE WHEN d.disk_total_gb > 0 THEN ROUND((d.disk_used_gb::numeric / d.disk_total_gb::numeric) * 100, 1) END)::real AS disk_usage_percent,
       (d.disk_total_gb - d.disk_used_gb) AS disk_free_gb,
       d.net_rx_mb, d.net_tx_mb, d.rx_delta_mb, d.tx_delta_mb,
       CASE WHEN d.dt_sec > 0 AND d.rx_delta_mb IS NOT NULL THEN (d.rx_delta_mb::numeric * 8.0 / d.dt_sec) END AS rx_mbps,
       CASE WHEN d.dt_sec > 0 AND d.tx_delta_mb IS NOT NULL THEN (d.tx_delta_mb::numeric * 8.0 / d.dt_sec) END AS tx_mbps
FROM d;

-- materialized view (minutely aggregates)
CREATE MATERIALIZED VIEW IF NOT EXISTS server.metrics_minutely AS
SELECT
  date_trunc('minute', "timestamp") AS minute_ts,
  avg(cpu_usage) AS cpu_avg,
  max(cpu_usage) AS cpu_max,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY cpu_usage) AS cpu_p95,
  avg(ram_usage_percent)  AS ram_pct_avg,
  max(ram_usage_percent)  AS ram_pct_max,
  avg(swap_usage_percent) AS swap_pct_avg,
  max(swap_usage_percent) AS swap_pct_max,
  avg(disk_usage_percent) AS disk_pct_avg,
  max(disk_usage_percent) AS disk_pct_max,
  avg(rx_mbps) AS rx_mbps_avg,
  avg(tx_mbps) AS tx_mbps_avg,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY rx_mbps) AS rx_mbps_p95,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY tx_mbps) AS tx_mbps_p95
FROM server.v_metrics_enriched
GROUP BY 1;

-- уникальный индекс для REFRESH CONCURRENTLY
CREATE UNIQUE INDEX IF NOT EXISTS metrics_minutely_pk ON server.metrics_minutely (minute_ts);

-- функция для рефреша
CREATE OR REPLACE FUNCTION server.refresh_metrics_minutely(p_concurrently boolean DEFAULT true)
RETURNS void AS $$
BEGIN
  IF p_concurrently THEN
    EXECUTE 'REFRESH MATERIALIZED VIEW CONCURRENTLY server.metrics_minutely';
  ELSE
    EXECUTE 'REFRESH MATERIALIZED VIEW server.metrics_minutely';
  END IF;
END
$$ LANGUAGE plpgsql;
