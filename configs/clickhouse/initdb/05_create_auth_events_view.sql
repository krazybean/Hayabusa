-- Hayabusa auth events view
-- Flattens auth-relevant fields from security.events for readable detections and investigations.

CREATE OR REPLACE VIEW security.auth_events AS
SELECT
    ts,
    event_id,
    platform,
    schema_version,
    ingest_source,
    message,
    event_type,
    user,
    src_ip,
    host,
    status,
    source_kind,
    raw_event_id,
    logon_type,
    domain,
    auth_method,
    collector_name
FROM
(
    SELECT
        ts,
        event_id,
        platform,
        schema_version,
        ingest_source,
        message,
        coalesce(
            nullIf(fields['event_type'], ''),
            multiIf(
                positionCaseInsensitive(message, 'Failed password') > 0, 'login',
                positionCaseInsensitive(message, 'Accepted password') > 0, 'login',
                positionCaseInsensitive(message, 'Accepted publickey') > 0, 'login',
                ''
            )
        ) AS event_type,
        coalesce(
            nullIf(fields['user'], ''),
            nullIf(extract(message, 'for invalid user ([^ ]+)'), ''),
            nullIf(extract(message, 'for ([^ ]+) from'), ''),
            nullIf(extract(message, 'Accepted (?:password|publickey) for ([^ ]+) from'), ''),
            ''
        ) AS user,
        coalesce(
            nullIf(fields['src_ip'], ''),
            nullIf(extract(message, 'from ([0-9A-Fa-f:\\.]+)'), ''),
            ''
        ) AS src_ip,
        coalesce(
            nullIf(fields['host'], ''),
            nullIf(fields['computer'], ''),
            nullIf(fields['hostname'], ''),
            ''
        ) AS host,
        coalesce(
            multiIf(
                lowerUTF8(nullIf(fields['status'], '')) = 'failed', 'failure',
                lowerUTF8(nullIf(fields['status'], '')) = 'failure', 'failure',
                lowerUTF8(nullIf(fields['status'], '')) = 'successful', 'success',
                lowerUTF8(nullIf(fields['status'], '')) = 'success', 'success',
                nullIf(fields['status'], '')
            ),
            multiIf(
                positionCaseInsensitive(message, 'Accepted password') > 0, 'success',
                positionCaseInsensitive(message, 'Accepted publickey') > 0, 'success',
                positionCaseInsensitive(message, 'Failed password') > 0, 'failure',
                ''
            )
        ) AS status,
        coalesce(
            nullIf(fields['source_kind'], ''),
            multiIf(
                ingest_source = 'vector-windows-endpoint', 'windows_auth',
                ingest_source = 'vector-linux-ssh', 'linux_ssh',
                positionCaseInsensitive(message, 'sshd') > 0, 'linux_ssh',
                ''
            )
        ) AS source_kind,
        coalesce(
            nullIf(fields['raw_event_id'], ''),
            nullIf(fields['event_id'], ''),
            ''
        ) AS raw_event_id,
        coalesce(nullIf(fields['logon_type'], ''), '') AS logon_type,
        coalesce(nullIf(fields['domain'], ''), '') AS domain,
        coalesce(
            nullIf(fields['auth_method'], ''),
            multiIf(
                positionCaseInsensitive(message, 'Accepted publickey') > 0, 'publickey',
                positionCaseInsensitive(message, 'Accepted password') > 0, 'password',
                positionCaseInsensitive(message, 'Failed password') > 0, 'password',
                ''
            )
        ) AS auth_method,
        coalesce(nullIf(fields['collector_name'], ''), '') AS collector_name
    FROM security.events
)
WHERE event_type IN ('login', 'auth.login');
