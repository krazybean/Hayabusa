-- Hayabusa detection output table
-- Stores triggered detections from the detection service.

CREATE TABLE IF NOT EXISTS security.alert_candidates
(
    ts              DateTime64(3, 'UTC') DEFAULT now64(3),
    rule_id         String,
    rule_name       String,
    severity        LowCardinality(String),
    hits            UInt64,
    threshold_op    LowCardinality(String),
    threshold_value UInt64,
    query           String,
    details         String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(ts)
ORDER BY (ts, rule_id)
TTL ts + INTERVAL 30 DAY;
