package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestEvaluateThreshold(t *testing.T) {
	tests := []struct {
		hits uint64
		op string
		threshold uint64
		want bool
	}{
		{5, "gt", 4, true},
		{4, "gt", 4, false},
		{4, "gte", 4, true},
		{4, "eq", 4, true},
		{3, "lt", 4, true},
		{4, "lte", 4, true},
		{4, "bogus", 4, false},
	}
	for _, tc := range tests {
		if got := evaluateThreshold(tc.hits, tc.op, tc.threshold); got != tc.want {
			t.Fatalf("evaluateThreshold(%d,%q,%d)=%v want %v", tc.hits, tc.op, tc.threshold, got, tc.want)
		}
	}
}

func TestNormalizeCSVAndSuppression(t *testing.T) {
	got := normalizeCSV(" Admin,admin, SERVICE , ")
	if len(got) != 2 || got[0] != "admin" || got[1] != "service" {
		t.Fatalf("unexpected normalizeCSV result: %#v", got)
	}

	r := rule{
		SuppressionComputersCSV: "Host-A,HOST-B",
		SuppressionUsersCSV: "Admin",
		SuppressionComputerExpr: "lowerUTF8(endpoint_id)",
		SuppressionUserExpr: "lowerUTF8(principal)",
	}
	condition := buildSuppressionCondition(r)
	for _, want := range []string{
		"lowerUTF8(endpoint_id) NOT IN ('host-a', 'host-b')",
		"lowerUTF8(principal) NOT IN ('admin')",
	} {
		if !strings.Contains(condition, want) {
			t.Fatalf("condition %q missing %q", condition, want)
		}
	}
}

func TestRenderRuleSQL(t *testing.T) {
	r := rule{
		ID: "test_rule",
		Name: "Test",
		ThresholdOp: "gte",
		ThresholdValue: 4,
		ThresholdAttempts: 4,
		ThresholdDistinctUsers: 3,
		ThresholdDistinctIPs: 2,
		ThresholdFailures: 5,
		WindowMinutes: 10,
		SuppressionComputerExpr: "endpoint_id",
		SuppressionUserExpr: "principal",
	}
	sql, err := renderRuleSQL(r, "SELECT {{WINDOW_MINUTES}}, {{THRESHOLD_ATTEMPTS}}, '{{SUPPRESSION_CONDITION}}';")
	if err != nil {
		t.Fatalf("renderRuleSQL: %v", err)
	}
	if strings.Contains(sql, "{{") {
		t.Fatalf("unresolved placeholder: %s", sql)
	}
	if !strings.Contains(sql, "SELECT 10, 4, '1 = 1'") {
		t.Fatalf("unexpected rendered SQL: %s", sql)
	}
}

func TestRenderRuleSQLRejectsMissingSuppressionPlaceholder(t *testing.T) {
	r := rule{
		SuppressionComputersCSV: "host-a",
		SuppressionComputerExpr: "endpoint_id",
	}
	if _, err := renderRuleSQL(r, "SELECT 1"); err == nil {
		t.Fatalf("expected suppression placeholder validation error")
	}
}

func TestParseDetectionRow(t *testing.T) {
	line := strings.Join([]string{
		"5", "alice", "10.0.0.1", "host-a",
		"2026-09-21 10:00:00.000", "2026-09-21 10:01:00.000",
		"3", "1", "windows_auth", "reason", "evidence", "{}", "2026-09-21 10:00:00.000",
	}, "	")
	row, err := parseDetectionRow(line)
	if err != nil {
		t.Fatalf("parseDetectionRow: %v", err)
	}
	if row.Hits != 5 || row.Principal != "alice" || row.DistinctUserCount != 3 || row.SourceKind != "windows_auth" {
		t.Fatalf("unexpected row: %#v", row)
	}
	if _, err := parseDetectionRow("1	too-short"); err == nil {
		t.Fatalf("expected short row to fail")
	}
}

func TestLoadEnabledRules(t *testing.T) {
	root := t.TempDir()
	ruleDir := filepath.Join(root, "rules")
	sqlDir := filepath.Join(root, "sql")
	metaDir := filepath.Join(root, "metadata")
	for _, dir := range []string{ruleDir, sqlDir, metaDir} {
		if err := os.MkdirAll(dir, 0o755); err != nil { t.Fatal(err) }
	}

	mustWrite := func(path, value string) {
		t.Helper()
		if err := os.WriteFile(path, []byte(value), 0o644); err != nil { t.Fatal(err) }
	}

	mustWrite(filepath.Join(ruleDir, "enabled.yaml"), "id: enabled\nname: Enabled\nthreshold_op: gte\nthreshold_value: 1\n")
	mustWrite(filepath.Join(ruleDir, "disabled.yaml"), "id: disabled\nname: Disabled\nthreshold_op: gte\nthreshold_value: 1\n")
	mustWrite(filepath.Join(sqlDir, "enabled.sql"), "SELECT 0, '', '', '', now(), now(), 0, 0, '', '', '', '', now()")
	mustWrite(filepath.Join(sqlDir, "disabled.sql"), "SELECT 0, '', '', '', now(), now(), 0, 0, '', '', '', '', now()")
	mustWrite(filepath.Join(metaDir, "enabled.yaml"), "id: enabled\nenabled: true\n")
	mustWrite(filepath.Join(metaDir, "disabled.yaml"), "id: disabled\nenabled: false\n")

	rules, err := loadEnabledRules(config{RuleDir: ruleDir, RuleSQLDir: sqlDir, RuleMetadataDir: metaDir})
	if err != nil {
		t.Fatalf("loadEnabledRules: %v", err)
	}
	if len(rules) != 1 || rules[0].Rule.ID != "enabled" {
		t.Fatalf("unexpected enabled rules: %#v", rules)
	}
}

func TestBuildFingerprintIsStable(t *testing.T) {
	got := buildFingerprint("password_spray", "alice", "10.0.0.1", "host-a", "windows_auth", "2026-09-21 10:00:00.000")
	want := "password_spray|alice|10.0.0.1|host-a|windows_auth|2026-09-21 10:00:00.000"
	if got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}
