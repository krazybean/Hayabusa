# Investigation Query Pack (Starter)

SQL-first starter hunts for local MVP triage against ClickHouse.

Run queries with:

```bash
curl -s http://localhost:8123 --data-binary "<QUERY> FORMAT PrettyCompact"
```

## 1) Latest endpoint security events

```sql
SELECT ts, fields['computer'] AS computer, fields['event_id'] AS event_id, message
FROM security.events
WHERE ingest_source = 'vector-windows-endpoint'
ORDER BY ts DESC
LIMIT 50
```

## 2) Failed logon volume by host (last 60m)

```sql
SELECT fields['computer'] AS computer, count() AS failed_logons
FROM security.events
WHERE ts > now() - INTERVAL 60 MINUTE
  AND ingest_source = 'vector-windows-endpoint'
  AND fields['event_id'] = '4625'
GROUP BY computer
ORDER BY failed_logons DESC
LIMIT 20
```

## 3) Account lockouts by host (last 24h)

```sql
SELECT fields['computer'] AS computer, count() AS lockouts
FROM security.events
WHERE ts > now() - INTERVAL 24 HOUR
  AND ingest_source = 'vector-windows-endpoint'
  AND fields['event_id'] = '4740'
GROUP BY computer
ORDER BY lockouts DESC
LIMIT 20
```

## 4) Service install events (4697/7045)

```sql
SELECT ts, fields['computer'] AS computer, fields['event_id'] AS event_id, message
FROM security.events
WHERE ts > now() - INTERVAL 24 HOUR
  AND ingest_source = 'vector-windows-endpoint'
  AND fields['event_id'] IN ('4697', '7045')
ORDER BY ts DESC
LIMIT 50
```

## 5) Privileged group membership changes (4728/4732/4756)

```sql
SELECT ts, fields['computer'] AS computer, fields['event_id'] AS event_id, message
FROM security.events
WHERE ts > now() - INTERVAL 24 HOUR
  AND ingest_source = 'vector-windows-endpoint'
  AND fields['event_id'] IN ('4728', '4732', '4756')
ORDER BY ts DESC
LIMIT 50
```

## 6) Correlated lockout candidates (4625 -> 4740 within 10m)

```sql
SELECT lock.fields['computer'] AS computer, min(fail.ts) AS first_failed_logon, lock.ts AS lockout_ts
FROM security.events AS lock
INNER JOIN security.events AS fail
  ON fail.fields['computer'] = lock.fields['computer']
  AND fail.ingest_source = 'vector-windows-endpoint'
  AND fail.fields['event_id'] = '4625'
  AND fail.ts <= lock.ts
  AND fail.ts >= lock.ts - INTERVAL 10 MINUTE
WHERE lock.ts > now() - INTERVAL 24 HOUR
  AND lock.ingest_source = 'vector-windows-endpoint'
  AND lock.fields['event_id'] = '4740'
  AND lock.fields['computer'] != ''
GROUP BY computer, lock.ts
ORDER BY lockout_ts DESC
LIMIT 50
```

## 7) Top ingest sources by event volume (last 60m)

```sql
SELECT ingest_source, count() AS events
FROM security.events
WHERE ts > now() - INTERVAL 60 MINUTE
GROUP BY ingest_source
ORDER BY events DESC
```

## 8) Latest detection candidates

```sql
SELECT ts, rule_id, severity, hits, threshold_op, threshold_value
FROM security.alert_candidates
ORDER BY ts DESC
LIMIT 50
```

## 9) Most frequent triggered rules (last 24h)

```sql
SELECT rule_id, count() AS trigger_count, max(hits) AS max_hits
FROM security.alert_candidates
WHERE ts > now() - INTERVAL 24 HOUR
GROUP BY rule_id
ORDER BY trigger_count DESC
LIMIT 20
```

## 10) Storage footprint check

```sql
SELECT
  toUInt64(ifNull(sum(bytes_on_disk), 0)) AS events_bytes,
  toUInt64(1073741824) AS budget_bytes
FROM system.parts
WHERE active
  AND database = 'security'
  AND table = 'events'
```
