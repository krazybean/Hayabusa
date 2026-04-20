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
  '' AS principal,
  source_ip,
  endpoint_id,
  window_start,
  window_end,
  targeted_users AS distinct_user_count,
  1 AS distinct_ip_count,
  source_kind,
  concat('Source ', source_ip, ' targeted multiple usernames on ', endpoint_id) AS reason,
  concat(
    toString(targeted_users), ' usernames targeted across ',
    toString(failed_attempts), ' failed attempts. Examples: ',
    sampled_users
  ) AS evidence_summary,
  concat(
    '{"source_ip":"', source_ip,
    '","endpoint_id":"', endpoint_id,
    '","targeted_users":', toString(targeted_users),
    ',"failed_attempts":', toString(failed_attempts),
    ',"sampled_users":"', sampled_users,
    '"}'
  ) AS details,
  toStartOfInterval(window_end, INTERVAL {{WINDOW_MINUTES}} MINUTE) AS window_bucket
FROM
(
  SELECT
    source_ip,
    endpoint_id,
    source_kind,
    uniqExact(principal) AS targeted_users,
    count() AS failed_attempts,
    arrayStringConcat(arraySlice(arraySort(groupUniqArray(principal)), 1, 5), ', ') AS sampled_users,
    min(ts) AS window_start,
    max(ts) AS window_end
  FROM recent_failures
  WHERE principal != ''
    AND source_ip != ''
    AND {{SUPPRESSION_CONDITION}}
  GROUP BY source_ip, endpoint_id, source_kind
  HAVING targeted_users >= {{THRESHOLD_DISTINCT_USERS}}
    AND failed_attempts >= {{THRESHOLD_ATTEMPTS}}
  ORDER BY targeted_users DESC, failed_attempts DESC, window_end DESC
  LIMIT 1
)
