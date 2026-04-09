-- Hayabusa endpoint activity view
-- Minimal first-host visibility for the real Windows endpoint milestone.

CREATE OR REPLACE VIEW security.endpoint_activity AS
SELECT
    endpoint_id,
    lane,
    first_seen,
    last_seen,
    total_events,
    dateDiff('minute', last_seen, now()) AS minutes_since_last_seen,
    multiIf(
        dateDiff('minute', last_seen, now()) <= 15, 'active',
        dateDiff('minute', last_seen, now()) <= 60, 'idle',
        'stale'
    ) AS status
FROM
(
    SELECT
        coalesce(
            nullIf(fields['computer'], ''),
            nullIf(fields['hostname'], ''),
            nullIf(fields['host'], ''),
            'unknown'
        ) AS endpoint_id,
        ingest_source AS lane,
        min(ts) AS first_seen,
        max(ts) AS last_seen,
        count() AS total_events
    FROM security.events
    GROUP BY endpoint_id, lane
)
WHERE endpoint_id != 'unknown';
