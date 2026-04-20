-- Manual detection verification stub for security_user_multi_source_burst
-- 1) Confirms required alert_candidates columns are present.
SELECT name, type
FROM system.columns
WHERE database = 'security'
  AND table = 'alert_candidates'
  AND name IN ('ts','rule_id','severity','hits','principal','source_ip','endpoint_id','reason')
ORDER BY name;

-- 2) Shows the latest matching alerts for this rule.
SELECT
  ts,
  rule_id,
  severity,
  hits,
  principal,
  source_ip,
  endpoint_id,
  reason
FROM security.alert_candidates
WHERE rule_id = 'security_user_multi_source_burst'
ORDER BY ts DESC
LIMIT 10;
