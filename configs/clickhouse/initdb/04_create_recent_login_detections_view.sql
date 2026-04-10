-- Hayabusa recent login detections view
-- Operator-friendly projection of detection output with explainable context.

CREATE OR REPLACE VIEW security.recent_login_detections AS
SELECT
    ts,
    rule_id,
    rule_name,
    if(alert_type = '', rule_id, alert_type) AS alert_type,
    if(alert_fingerprint = '', 'n/a', alert_fingerprint) AS alert_fingerprint,
    severity,
    hits,
    attempt_count,
    if(entity_user = '', if(principal = '', 'n/a', principal), entity_user) AS entity_user,
    if(entity_src_ip = '', if(source_ip = '', 'n/a', source_ip), entity_src_ip) AS entity_src_ip,
    if(entity_host = '', if(endpoint_id = '', 'n/a', endpoint_id), entity_host) AS entity_host,
    first_seen_ts,
    last_seen_ts,
    window_bucket,
    distinct_user_count,
    distinct_ip_count,
    if(source_kind = '', 'n/a', source_kind) AS source_kind,
    reason,
    evidence_summary,
    if(workflow_state = '', 'new', workflow_state) AS workflow_state,
    details
FROM security.alert_candidates;
