WITH auth_events AS
(
  SELECT
    ts,
    user AS principal,
    src_ip AS source_ip,
    host AS endpoint_id,
    source_kind,
    multiIf(status = 'success', 'success', status = 'failure', 'failed', '') AS auth_status
  FROM security.auth_events
  WHERE ts > now() - INTERVAL {{WINDOW_MINUTES}} MINUTE
    AND ingest_source != 'vector-windows-endpoint'
)
SELECT
  failed_attempts AS hits,
  principal,
  source_ip,
  endpoint_id,
  first_failure AS window_start,
  first_success AS window_end,
  1 AS distinct_user_count,
  1 AS distinct_ip_count,
  source_kind,
  concat('Successful login followed repeated failures for ', principal, ' from ', source_ip, ' on ', endpoint_id) AS reason,
  concat(
    toString(failed_attempts), ' failed attempts before success within ',
    toString({{WINDOW_MINUTES}}), ' minutes'
  ) AS evidence_summary,
  concat(
    '{"principal":"', principal,
    '","source_ip":"', source_ip,
    '","endpoint_id":"', endpoint_id,
    '","failed_attempts":', toString(failed_attempts),
    ',"first_failure":"', toString(first_failure),
    '","first_success":"', toString(first_success),
    '"}'
  ) AS details,
  toStartOfInterval(first_success, INTERVAL {{WINDOW_MINUTES}} MINUTE) AS window_bucket
FROM
(
  SELECT
    principal,
    source_ip,
    endpoint_id,
    source_kind,
    countIf(auth_status = 'failed') AS failed_attempts,
    minIf(ts, auth_status = 'failed') AS first_failure,
    maxIf(ts, auth_status = 'failed') AS last_failure,
    minIf(ts, auth_status = 'success') AS first_success
  FROM auth_events
  WHERE principal != ''
    AND source_ip != ''
    AND auth_status != ''
    AND {{SUPPRESSION_CONDITION}}
  GROUP BY principal, source_ip, endpoint_id, source_kind
  HAVING failed_attempts >= {{THRESHOLD_FAILURES}}
    AND first_success > toDateTime64(0, 3, 'UTC')
    AND first_success >= last_failure
  ORDER BY failed_attempts DESC, first_success DESC
  LIMIT 1
)
