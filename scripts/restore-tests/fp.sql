-- Exact, version-portable DB fingerprint: public-table count | grand-total exact row count | extension set.
-- Uses query_to_xml(count(*)) per table to get an EXACT total without per-table shell loops.
SELECT
  (SELECT count(*) FROM information_schema.tables WHERE table_schema='public')::text
  || '|' ||
  (SELECT coalesce(sum(
       (xpath('/row/c/text()',
              query_to_xml(format('SELECT count(*) AS c FROM %I.%I', schemaname, relname),
                           false, true, '')))[1]::text::bigint), 0)::text
     FROM pg_stat_user_tables)
  || '|' ||
  (SELECT coalesce(string_agg(extname, ',' ORDER BY extname), '') FROM pg_extension)
  AS fingerprint;
