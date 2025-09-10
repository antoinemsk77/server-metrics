-- 02_partitions.sql
-- функции для партиционирования и архивации

-- создаём текущую и следующую месячную партицию
CREATE OR REPLACE FUNCTION server.ensure_monthly_partitions() RETURNS void AS $$
DECLARE
  m_start date;
  m_end   date;
  p_name  text;
BEGIN
  FOR m_start IN
    SELECT date_trunc('month', now())::date
    UNION ALL
    SELECT date_trunc('month', now() + interval '1 month')::date
  LOOP
    m_end  := (m_start + interval '1 month')::date;
    p_name := 'metrics_' || to_char(m_start, 'YYYYMM');

    IF to_regclass('server.'||p_name) IS NULL THEN
      EXECUTE format(
        'CREATE TABLE server.%I PARTITION OF server.metrics
         FOR VALUES FROM (%L) TO (%L);',
        p_name, m_start::timestamptz, m_end::timestamptz
      );
      EXECUTE format('CREATE INDEX %I_ts_idx ON server.%I("timestamp");',
                     p_name || '_ts_idx', p_name);
    END IF;
  END LOOP;
END
$$ LANGUAGE plpgsql;

-- перенос прошлой партиции в архив (пока в той же схеме)
CREATE OR REPLACE FUNCTION server.archive_previous_month() RETURNS void AS $$
DECLARE
  prev_start date := (date_trunc('month', now()) - interval '1 month')::date;
  prev_end   date := date_trunc('month', now())::date;
  part_name  text := 'metrics_' || to_char(prev_start, 'YYYYMM');
BEGIN
  PERFORM server.ensure_monthly_partitions();

  IF to_regclass('server.'||part_name) IS NULL THEN
    RAISE NOTICE 'Partition % not found in schema server, nothing to archive', part_name;
    RETURN;
  END IF;

  EXECUTE format('ALTER TABLE server.metrics DETACH PARTITION server.%I;', part_name);
  -- можно перенести в другую схему, пока оставляем в server
  -- EXECUTE format('ALTER TABLE server.%I SET SCHEMA archive;', part_name);

  EXECUTE format('CREATE INDEX IF NOT EXISTS %I_ts_idx ON server.%I("timestamp");',
                 part_name || '_ts_idx', part_name);
END
$$ LANGUAGE plpgsql;
