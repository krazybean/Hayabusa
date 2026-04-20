SELECT
  hits,
  sample_user AS principal,
  sample_source_ip AS source_ip,
  endpoint_id,
  window_start,
  window_end,
  distinct_user_count,
  distinct_ip_count,
  'windows_auth' AS source_kind,
  concat('Repeated Windows failed logons detected on ', endpoint_id) AS reason,
  concat(toString(hits), ' failed logons within ', toString({{WINDOW_MINUTES}}), ' minutes') AS evidence_summary,
  concat(
    '{"endpoint_id":"', endpoint_id,
    '","sample_user":"', sample_user,
    '","sample_source_ip":"', sample_source_ip,
    '","sample_logon_type":"', sample_logon_type,
    '","failed_attempts":', toString(hits),
    ',"window_minutes":', toString({{WINDOW_MINUTES}}),
    '}'
  ) AS details,
  toStartOfInterval(window_end, INTERVAL {{WINDOW_MINUTES}} MINUTE) AS window_bucket
FROM
(
  SELECT
    if(host = '', 'unknown', host) AS endpoint_id,
    count() AS hits,
    anyIf(user, user != '') AS sample_user,
    anyIf(src_ip, src_ip != '') AS sample_source_ip,
    anyIf(logon_type, logon_type != '') AS sample_logon_type,
    uniqExactIf(user, user != '') AS distinct_user_count,
    uniqExactIf(src_ip, src_ip != '') AS distinct_ip_count,
    min(ts) AS window_start,
    max(ts) AS window_end
  FROM security.auth_events
  WHERE ts > now() - INTERVAL {{WINDOW_MINUTES}} MINUTE
    AND ingest_source = 'vector-windows-endpoint'
    AND status = 'failure'
    AND {{SUPPRESSION_CONDITION}}
  GROUP BY endpoint_id
  ORDER BY hits DESC, window_end DESC
  LIMIT 1
)
