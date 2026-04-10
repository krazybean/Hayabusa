-- Hayabusa detection output table
-- Stores triggered detections from the detection service.

CREATE TABLE IF NOT EXISTS security.alert_candidates
(
    ts               DateTime64(3, 'UTC') DEFAULT now64(3),
    rule_id          String,
    rule_name        String,
    alert_type       LowCardinality(String) DEFAULT '',
    alert_fingerprint String DEFAULT '',
    severity         LowCardinality(String),
    hits             UInt64,
    attempt_count    UInt64 DEFAULT 0,
    principal        String DEFAULT '',
    entity_user      String DEFAULT '',
    source_ip        String DEFAULT '',
    entity_src_ip    String DEFAULT '',
    endpoint_id      String DEFAULT '',
    entity_host      String DEFAULT '',
    window_start     DateTime64(3, 'UTC') DEFAULT now64(3),
    first_seen_ts    DateTime64(3, 'UTC') DEFAULT now64(3),
    window_end       DateTime64(3, 'UTC') DEFAULT now64(3),
    last_seen_ts     DateTime64(3, 'UTC') DEFAULT now64(3),
    window_bucket    DateTime64(3, 'UTC') DEFAULT now64(3),
    distinct_user_count UInt64 DEFAULT 0,
    distinct_ip_count UInt64 DEFAULT 0,
    source_kind      LowCardinality(String) DEFAULT '',
    reason           String DEFAULT '',
    evidence_summary String DEFAULT '',
    workflow_state   LowCardinality(String) DEFAULT 'new',
    threshold_op     LowCardinality(String),
    threshold_value  UInt64,
    query            String,
    details          String DEFAULT ''
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(ts)
ORDER BY (ts, rule_id)
TTL ts + INTERVAL 30 DAY;
