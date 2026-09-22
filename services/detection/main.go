package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"

	"go.yaml.in/yaml/v3"
)

type config struct {
	RuleDir         string
	RuleSQLDir      string
	RuleMetadataDir string
	ClickHouseURL   string
	PollInterval    time.Duration
	HeartbeatFile   string
}

type rule struct {
	ID                        string `yaml:"id"`
	Name                      string `yaml:"name"`
	Severity                  string `yaml:"severity"`
	AlertType                 string `yaml:"alert_type"`
	ThresholdOp               string `yaml:"threshold_op"`
	ThresholdValue            uint64 `yaml:"threshold_value"`
	ThresholdAttempts         uint64 `yaml:"threshold_attempts"`
	ThresholdDistinctUsers    uint64 `yaml:"threshold_distinct_users"`
	ThresholdDistinctIPs      uint64 `yaml:"threshold_distinct_ips"`
	ThresholdFailures         uint64 `yaml:"threshold_failures"`
	WindowMinutes             uint64 `yaml:"window_minutes"`
	CooldownSeconds           uint64 `yaml:"cooldown_seconds"`
	SuppressionComputersCSV   string `yaml:"suppression_computers_csv"`
	SuppressionUsersCSV       string `yaml:"suppression_users_csv"`
	SuppressionComputerExpr   string `yaml:"suppression_computer_expr"`
	SuppressionUserExpr       string `yaml:"suppression_user_expr"`
}

type metadata struct {
	ID      string `yaml:"id"`
	Enabled *bool  `yaml:"enabled"`
}

type detectionRow struct {
	Hits              uint64
	Principal         string
	SourceIP          string
	EndpointID        string
	WindowStart       string
	WindowEnd         string
	DistinctUserCount uint64
	DistinctIPCount   uint64
	SourceKind        string
	Reason            string
	EvidenceSummary   string
	Details           string
	WindowBucket      string
}

type clickhouseClient struct {
	baseURL string
	client  *http.Client
}

func main() {
	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("configuration error: %v", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	ch := clickhouseClient{
		baseURL: strings.TrimRight(cfg.ClickHouseURL, "/") + "/",
		client:  &http.Client{Timeout: 15 * time.Second},
	}
	if err := ensureSchema(ctx, ch); err != nil {
		log.Fatalf("ensure schema: %v", err)
	}

	log.Printf("detection service started polling=%s rules=%s sql_rules=%s metadata=%s", cfg.PollInterval, cfg.RuleDir, cfg.RuleSQLDir, cfg.RuleMetadataDir)
	runCycle(ctx, cfg, ch)
	ticker := time.NewTicker(cfg.PollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			log.Printf("detection service shutting down")
			return
		case <-ticker.C:
			runCycle(ctx, cfg, ch)
		}
	}
}

func loadConfig() (config, error) {
	pollSeconds, err := strconv.Atoi(envOrDefault("DETECTION_POLL_SECONDS", "30"))
	if err != nil || pollSeconds < 1 {
		return config{}, fmt.Errorf("DETECTION_POLL_SECONDS must be a positive integer")
	}
	return config{
		RuleDir:         envOrDefault("RULE_DIR", "/etc/hayabusa/rules"),
		RuleSQLDir:      envOrDefault("RULE_SQL_DIR", "/etc/hayabusa/detections/rules"),
		RuleMetadataDir: envOrDefault("RULE_METADATA_DIR", "/etc/hayabusa/detections/metadata"),
		ClickHouseURL:   envOrDefault("CLICKHOUSE_URL", "http://clickhouse:8123/"),
		PollInterval:    time.Duration(pollSeconds) * time.Second,
		HeartbeatFile:   envOrDefault("HEARTBEAT_FILE", "/tmp/detection-heartbeat"),
	}, nil
}

func runCycle(ctx context.Context, cfg config, ch clickhouseClient) {
	rules, err := loadEnabledRules(cfg)
	if err != nil {
		log.Printf("rule discovery failed: %v", err)
		writeHeartbeat(cfg.HeartbeatFile)
		return
	}
	if len(rules) == 0 {
		log.Printf("no enabled detection rules found")
	}
	for _, loaded := range rules {
		if err := runRule(ctx, ch, loaded.Rule, loaded.SQL); err != nil {
			log.Printf("rule=%s failed: %v", loaded.Rule.ID, err)
		}
	}
	writeHeartbeat(cfg.HeartbeatFile)
}

type loadedRule struct {
	Rule rule
	SQL  string
}

func loadEnabledRules(cfg config) ([]loadedRule, error) {
	disabled, err := disabledRuleIDs(cfg.RuleMetadataDir)
	if err != nil {
		return nil, err
	}
	configs, err := loadRuleConfigs(cfg.RuleDir)
	if err != nil {
		return nil, err
	}

	matches, err := filepath.Glob(filepath.Join(cfg.RuleSQLDir, "*.sql"))
	if err != nil {
		return nil, err
	}
	sort.Strings(matches)

	var out []loadedRule
	for _, path := range matches {
		id := strings.TrimSuffix(filepath.Base(path), ".sql")
		if disabled[id] {
			continue
		}
		r, ok := configs[id]
		if !ok {
			log.Printf("skipping %s: no rule config with id=%s", path, id)
			continue
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("read SQL %s: %w", path, err)
		}
		sql := strings.TrimSpace(string(data))
		if sql == "" {
			log.Printf("skipping %s: empty SQL", id)
			continue
		}
		applyRuleDefaults(&r)
		if err := validateRule(r); err != nil {
			log.Printf("skipping %s: %v", id, err)
			continue
		}
		out = append(out, loadedRule{Rule: r, SQL: sql})
	}
	return out, nil
}

func disabledRuleIDs(dir string) (map[string]bool, error) {
	out := map[string]bool{}
	matches, err := filepath.Glob(filepath.Join(dir, "*.yaml"))
	if err != nil {
		return nil, err
	}
	for _, path := range matches {
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		var m metadata
		if err := yaml.Unmarshal(data, &m); err != nil {
			return nil, fmt.Errorf("parse metadata %s: %w", path, err)
		}
		if m.ID != "" && m.Enabled != nil && !*m.Enabled {
			out[m.ID] = true
		}
	}
	return out, nil
}

func loadRuleConfigs(dir string) (map[string]rule, error) {
	out := map[string]rule{}
	matches, err := filepath.Glob(filepath.Join(dir, "*.yaml"))
	if err != nil {
		return nil, err
	}
	for _, path := range matches {
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		var r rule
		if err := yaml.Unmarshal(data, &r); err != nil {
			return nil, fmt.Errorf("parse rule %s: %w", path, err)
		}
		if r.ID != "" {
			out[r.ID] = r
		}
	}
	return out, nil
}

func applyRuleDefaults(r *rule) {
	if r.Severity == "" { r.Severity = "medium" }
	if r.ThresholdOp == "" { r.ThresholdOp = "gte" }
	if r.ThresholdValue == 0 { r.ThresholdValue = 1 }
	if r.WindowMinutes == 0 { r.WindowMinutes = 5 }
	if r.AlertType == "" { r.AlertType = r.ID }
	if r.ThresholdAttempts == 0 { r.ThresholdAttempts = r.ThresholdValue }
	if r.ThresholdDistinctUsers == 0 { r.ThresholdDistinctUsers = r.ThresholdValue }
	if r.ThresholdDistinctIPs == 0 { r.ThresholdDistinctIPs = r.ThresholdValue }
	if r.ThresholdFailures == 0 { r.ThresholdFailures = r.ThresholdValue }
	if r.SuppressionComputerExpr == "" {
		r.SuppressionComputerExpr = "lowerUTF8(ifNull(fields['computer'], ifNull(fields['hostname'], '')))"
	}
	if r.SuppressionUserExpr == "" {
		r.SuppressionUserExpr = "lowerUTF8(ifNull(fields['user'], ifNull(fields['username'], ifNull(fields['subject_user_name'], ifNull(fields['target_user_name'], '')))))"
	}
}

func validateRule(r rule) error {
	if r.ID == "" { return errors.New("missing id") }
	if r.Name == "" { return errors.New("missing name") }
	switch r.ThresholdOp {
	case "gt", "gte", "eq", "lt", "lte":
	default:
		return fmt.Errorf("unsupported threshold_op %q", r.ThresholdOp)
	}
	return nil
}

func runRule(ctx context.Context, ch clickhouseClient, r rule, rawSQL string) error {
	query, err := renderRuleSQL(r, rawSQL)
	if err != nil {
		return err
	}
	result, err := ch.query(ctx, appendFormat(query, "TabSeparated"))
	if err != nil {
		return err
	}
	line := firstNonEmptyLine(result)
	if line == "" {
		return nil
	}
	row, err := parseDetectionRow(line)
	if err != nil {
		return err
	}
	if !evaluateThreshold(row.Hits, r.ThresholdOp, r.ThresholdValue) {
		return nil
	}

	if row.WindowStart == "" { row.WindowStart = utcNowString() }
	if row.WindowEnd == "" { row.WindowEnd = utcNowString() }
	if row.WindowBucket == "" { row.WindowBucket = row.WindowEnd }
	if row.Reason == "" { row.Reason = "Triggered by Hayabusa detection service" }
	if row.EvidenceSummary == "" { row.EvidenceSummary = "No additional evidence summary provided" }
	if row.Details == "" { row.Details = "Triggered by Hayabusa detection service" }

	fingerprint := buildFingerprint(r.AlertType, row.Principal, row.SourceIP, row.EndpointID, row.SourceKind, row.WindowBucket)
	exists, err := alertExists(ctx, ch, fingerprint)
	if err != nil {
		return err
	}
	if exists {
		log.Printf("skipped already-recorded alert_type=%s fingerprint=%s", r.AlertType, fingerprint)
		return nil
	}
	if r.CooldownSeconds > 0 {
		recent, err := alertWithinCooldown(ctx, ch, fingerprint, r.CooldownSeconds)
		if err != nil { return err }
		if recent {
			log.Printf("suppressed alert_type=%s fingerprint=%s cooldown_seconds=%d", r.AlertType, fingerprint, r.CooldownSeconds)
			return nil
		}
	}

	if err := insertCandidate(ctx, ch, r, row, fingerprint, compactSQL(query)); err != nil {
		return err
	}
	log.Printf("triggered rule=%s hits=%d op=%s threshold=%d principal=%s source_ip=%s endpoint_id=%s", r.ID, row.Hits, r.ThresholdOp, r.ThresholdValue, row.Principal, row.SourceIP, row.EndpointID)
	return nil
}

func renderRuleSQL(r rule, sql string) (string, error) {
	condition := buildSuppressionCondition(r)
	if (strings.TrimSpace(r.SuppressionComputersCSV) != "" || strings.TrimSpace(r.SuppressionUsersCSV) != "") && !strings.Contains(sql, "{{SUPPRESSION_CONDITION}}") {
		return "", errors.New("suppression configured but SQL has no {{SUPPRESSION_CONDITION}} placeholder")
	}
	replacements := map[string]string{
		"{{SUPPRESSION_CONDITION}}": condition,
		"{{WINDOW_MINUTES}}": strconv.FormatUint(r.WindowMinutes, 10),
		"{{THRESHOLD_ATTEMPTS}}": strconv.FormatUint(r.ThresholdAttempts, 10),
		"{{THRESHOLD_DISTINCT_USERS}}": strconv.FormatUint(r.ThresholdDistinctUsers, 10),
		"{{THRESHOLD_DISTINCT_IPS}}": strconv.FormatUint(r.ThresholdDistinctIPs, 10),
		"{{THRESHOLD_FAILURES}}": strconv.FormatUint(r.ThresholdFailures, 10),
	}
	for from, to := range replacements {
		sql = strings.ReplaceAll(sql, from, to)
	}
	if strings.Contains(sql, "{{") {
		return "", fmt.Errorf("unresolved SQL placeholder")
	}
	return strings.TrimSuffix(strings.TrimSpace(sql), ";"), nil
}

func buildSuppressionCondition(r rule) string {
	var clauses []string
	if values := normalizeCSV(r.SuppressionComputersCSV); len(values) > 0 {
		clauses = append(clauses, fmt.Sprintf("%s NOT IN (%s)", r.SuppressionComputerExpr, sqlStringList(values)))
	}
	if values := normalizeCSV(r.SuppressionUsersCSV); len(values) > 0 {
		clauses = append(clauses, fmt.Sprintf("%s NOT IN (%s)", r.SuppressionUserExpr, sqlStringList(values)))
	}
	if len(clauses) == 0 { return "1 = 1" }
	return strings.Join(clauses, " AND ")
}

func normalizeCSV(value string) []string {
	seen := map[string]bool{}
	var out []string
	for _, item := range strings.Split(value, ",") {
		item = strings.ToLower(strings.TrimSpace(item))
		if item != "" && !seen[item] {
			seen[item] = true
			out = append(out, item)
		}
	}
	return out
}

func sqlStringList(values []string) string {
	quoted := make([]string, 0, len(values))
	for _, value := range values {
		quoted = append(quoted, "'"+escapeSQL(value)+"'")
	}
	return strings.Join(quoted, ", ")
}

func parseDetectionRow(line string) (detectionRow, error) {
	cols := strings.Split(line, "	")
	if len(cols) < 13 {
		return detectionRow{}, fmt.Errorf("detection query returned %d columns; expected 13", len(cols))
	}
	hits, err := strconv.ParseUint(cols[0], 10, 64)
	if err != nil { return detectionRow{}, fmt.Errorf("invalid hits %q", cols[0]) }
	users, err := parseUintDefault(cols[6])
	if err != nil { return detectionRow{}, fmt.Errorf("invalid distinct_user_count: %w", err) }
	ips, err := parseUintDefault(cols[7])
	if err != nil { return detectionRow{}, fmt.Errorf("invalid distinct_ip_count: %w", err) }
	return detectionRow{
		Hits: hits, Principal: cols[1], SourceIP: cols[2], EndpointID: cols[3],
		WindowStart: cols[4], WindowEnd: cols[5], DistinctUserCount: users,
		DistinctIPCount: ips, SourceKind: cols[8], Reason: cols[9],
		EvidenceSummary: cols[10], Details: cols[11], WindowBucket: cols[12],
	}, nil
}

func parseUintDefault(value string) (uint64, error) {
	if strings.TrimSpace(value) == "" { return 0, nil }
	return strconv.ParseUint(value, 10, 64)
}

func evaluateThreshold(hits uint64, op string, threshold uint64) bool {
	switch op {
	case "gt": return hits > threshold
	case "gte": return hits >= threshold
	case "eq": return hits == threshold
	case "lt": return hits < threshold
	case "lte": return hits <= threshold
	default: return false
	}
}

func buildFingerprint(alertType, principal, sourceIP, endpointID, sourceKind, windowBucket string) string {
	return strings.Join([]string{alertType, principal, sourceIP, endpointID, sourceKind, windowBucket}, "|")
}

func alertExists(ctx context.Context, ch clickhouseClient, fingerprint string) (bool, error) {
	q := fmt.Sprintf("SELECT count() FROM security.alert_candidates WHERE alert_fingerprint = '%s' FORMAT TabSeparated", escapeSQL(fingerprint))
	return queryCount(ctx, ch, q)
}

func alertWithinCooldown(ctx context.Context, ch clickhouseClient, fingerprint string, seconds uint64) (bool, error) {
	q := fmt.Sprintf("SELECT count() FROM security.alert_candidates WHERE alert_fingerprint = '%s' AND ts > now() - INTERVAL %d SECOND FORMAT TabSeparated", escapeSQL(fingerprint), seconds)
	return queryCount(ctx, ch, q)
}

func queryCount(ctx context.Context, ch clickhouseClient, q string) (bool, error) {
	out, err := ch.query(ctx, q)
	if err != nil { return false, err }
	n, err := strconv.ParseUint(strings.TrimSpace(out), 10, 64)
	if err != nil { return false, err }
	return n > 0, nil
}

func insertCandidate(ctx context.Context, ch clickhouseClient, r rule, row detectionRow, fingerprint, query string) error {
	sql := fmt.Sprintf(`
INSERT INTO security.alert_candidates
(rule_id, rule_name, alert_type, alert_fingerprint, severity, hits, attempt_count, principal, entity_user, source_ip, entity_src_ip, endpoint_id, entity_host, window_start, first_seen_ts, window_end, last_seen_ts, window_bucket, distinct_user_count, distinct_ip_count, source_kind, reason, evidence_summary, workflow_state, threshold_op, threshold_value, query, details)
VALUES
('%s','%s','%s','%s','%s',%d,%d,'%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s',%d,%d,'%s','%s','%s','new','%s',%d,'%s','%s')
`,
		escapeSQL(r.ID), escapeSQL(r.Name), escapeSQL(r.AlertType), escapeSQL(fingerprint), escapeSQL(r.Severity),
		row.Hits, row.Hits, escapeSQL(row.Principal), escapeSQL(row.Principal),
		escapeSQL(row.SourceIP), escapeSQL(row.SourceIP), escapeSQL(row.EndpointID), escapeSQL(row.EndpointID),
		escapeSQL(row.WindowStart), escapeSQL(row.WindowStart), escapeSQL(row.WindowEnd), escapeSQL(row.WindowEnd),
		escapeSQL(row.WindowBucket), row.DistinctUserCount, row.DistinctIPCount, escapeSQL(row.SourceKind),
		escapeSQL(row.Reason), escapeSQL(row.EvidenceSummary), escapeSQL(r.ThresholdOp), r.ThresholdValue,
		escapeSQL(query), escapeSQL(row.Details),
	)
	_, err := ch.query(ctx, sql)
	return err
}

func ensureSchema(ctx context.Context, ch clickhouseClient) error {
	_, err := ch.query(ctx, `
CREATE TABLE IF NOT EXISTS security.alert_candidates
(
    ts DateTime64(3, 'UTC') DEFAULT now64(3),
    rule_id String,
    rule_name String,
    alert_type LowCardinality(String) DEFAULT '',
    alert_fingerprint String DEFAULT '',
    severity LowCardinality(String),
    hits UInt64,
    attempt_count UInt64 DEFAULT 0,
    principal String DEFAULT '',
    entity_user String DEFAULT '',
    source_ip String DEFAULT '',
    entity_src_ip String DEFAULT '',
    endpoint_id String DEFAULT '',
    entity_host String DEFAULT '',
    window_start DateTime64(3, 'UTC') DEFAULT now64(3),
    first_seen_ts DateTime64(3, 'UTC') DEFAULT now64(3),
    window_end DateTime64(3, 'UTC') DEFAULT now64(3),
    last_seen_ts DateTime64(3, 'UTC') DEFAULT now64(3),
    window_bucket DateTime64(3, 'UTC') DEFAULT now64(3),
    distinct_user_count UInt64 DEFAULT 0,
    distinct_ip_count UInt64 DEFAULT 0,
    source_kind LowCardinality(String) DEFAULT '',
    reason String DEFAULT '',
    evidence_summary String DEFAULT '',
    workflow_state LowCardinality(String) DEFAULT 'new',
    threshold_op LowCardinality(String),
    threshold_value UInt64,
    query String,
    details String DEFAULT ''
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(ts)
ORDER BY (ts, rule_id)
TTL ts + INTERVAL 30 DAY
`)
	return err
}

func (c clickhouseClient) query(ctx context.Context, sql string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL, bytes.NewBufferString(sql))
	if err != nil { return "", err }
	resp, err := c.client.Do(req)
	if err != nil { return "", err }
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil { return "", err }
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("ClickHouse %s: %s", resp.Status, strings.TrimSpace(string(body)))
	}
	return string(body), nil
}

func appendFormat(sql, format string) string {
	return strings.TrimSuffix(strings.TrimSpace(sql), ";") + " FORMAT " + format
}

func firstNonEmptyLine(value string) string {
	for _, line := range strings.Split(value, "\n") {
		if strings.TrimSpace(line) != "" { return strings.TrimSuffix(line, "") }
	}
	return ""
}

func compactSQL(value string) string {
	return strings.Join(strings.Fields(value), " ")
}

func escapeSQL(value string) string {
	return strings.ReplaceAll(value, "'", "''")
}

func utcNowString() string {
	return time.Now().UTC().Format("2006-01-02 15:04:05.000")
}

func writeHeartbeat(path string) {
	if err := os.WriteFile(path, []byte(time.Now().UTC().Format(time.RFC3339)+"\n"), 0o644); err != nil {
		log.Printf("heartbeat write failed: %v", err)
	}
}

func envOrDefault(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" { return value }
	return fallback
}
