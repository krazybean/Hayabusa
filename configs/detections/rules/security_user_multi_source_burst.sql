WITH recent_failures AS
(
  SELECT
    ts,
    user AS principal,
    src_ip AS source_ip,
    host AS endpoint_id,
    source_kind
  FROM security.auth_events
  WHERE ts > now() - INTERVAL {{WINDOW_MINUTES}} MINUTE
    AND status = 'failure'
    AND ingest_source != 'vector-windows-endpoint'
)
SELECT
  failed_attempts AS hits,
  principal,
  '' AS source_ip,
  endpoint_id,
  window_start,
  window_end,
  1 AS distinct_user_count,
  source_count AS distinct_ip_count,
  source_kind,
  concat('Account ', principal, ' saw failed logins from multiple source IPs on ', endpoint_id) AS reason,
  concat(
    toString(source_count), ' source IPs across ',
    toString(failed_attempts), ' failed attempts. Examples: ',
    sampled_sources
  ) AS evidence_summary,
  concat(
    '{"principal":"', principal,
    '","endpoint_id":"', endpoint_id,
    '","source_count":', toString(source_count),
    ',"failed_attempts":', toString(failed_attempts),
    ',"sampled_sources":"', sampled_sources,
    '"}'
  ) AS details,
  toStartOfInterval(window_end, INTERVAL {{WINDOW_MINUTES}} MINUTE) AS window_bucket
FROM
(
  SELECT
    principal,
    endpoint_id,
    source_kind,
    uniqExact(source_ip) AS source_count,
    count() AS failed_attempts,
    arrayStringConcat(arraySlice(arraySort(groupUniqArray(source_ip)), 1, 5), ', ') AS sampled_sources,
    min(ts) AS window_start,
    max(ts) AS window_end
  FROM recent_failures
  WHERE principal != ''
    AND source_ip != ''
    AND {{SUPPRESSION_CONDITION}}
  GROUP BY principal, endpoint_id, source_kind
  HAVING source_count >= {{THRESHOLD_DISTINCT_IPS}}
    AND failed_attempts >= {{THRESHOLD_ATTEMPTS}}
  ORDER BY source_count DESC, failed_attempts DESC, window_end DESC
  LIMIT 1
)
