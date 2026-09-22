package main

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestParseClickHouseEndpoint(t *testing.T) {
	tests := []struct {
		name   string
		input  string
		addr   string
		secure bool
		ok     bool
	}{
		{name: "http", input: "http://clickhouse:8123", addr: "clickhouse:8123", ok: true},
		{name: "https", input: "https://example.test:8443", addr: "example.test:8443", secure: true, ok: true},
		{name: "implicit http", input: "clickhouse:8123", addr: "clickhouse:8123", ok: true},
		{name: "missing host", input: "http://", ok: false},
		{name: "unsupported scheme", input: "tcp://clickhouse:9000", ok: false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			addr, secure, err := parseClickHouseEndpoint(tc.input)
			if tc.ok && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !tc.ok {
				if err == nil {
					t.Fatalf("expected error")
				}
				return
			}
			if addr != tc.addr || secure != tc.secure {
				t.Fatalf("got addr=%q secure=%v; want addr=%q secure=%v", addr, secure, tc.addr, tc.secure)
			}
		})
	}
}

func TestParseEventTime(t *testing.T) {
	tests := []string{
		"2026-09-21 12:34:56.789",
		"2026-09-21 12:34:56.789123",
		"2026-09-21 12:34:56",
		"2026-09-21T12:34:56Z",
		"2026-09-21T12:34:56.789123Z",
	}
	for _, input := range tests {
		t.Run(input, func(t *testing.T) {
			got, err := parseEventTime(input)
			if err != nil {
				t.Fatalf("parseEventTime(%q): %v", input, err)
			}
			if got.Location() != time.UTC {
				t.Fatalf("timestamp not normalized to UTC: %v", got.Location())
			}
		})
	}

	for _, input := range []string{"", "not-a-time"} {
		if _, err := parseEventTime(input); err == nil {
			t.Fatalf("expected parseEventTime(%q) to fail", input)
		}
	}
}

func TestDecodeAndValidateEvent(t *testing.T) {
	valid := `{"ts":"2026-09-21T12:34:56Z","platform":"windows","schema_version":"hayabusa.event.v1","ingest_source":"collector-test","message":"login","fields":{"event_id":"4625","attempt":7}}`

	event, err := decodeAndValidateEvent([]byte(valid))
	if err != nil {
		t.Fatalf("valid event rejected: %v", err)
	}
	if got := event.Fields["attempt"]; got != json.Number("7") {
		t.Fatalf("numeric field lost precision-preserving representation: %#v", got)
	}

	tests := []struct {
		name    string
		payload string
	}{
		{name: "empty", payload: ""},
		{name: "malformed json", payload: "{"},
		{name: "missing timestamp", payload: `{"platform":"windows","schema_version":"hayabusa.event.v1","ingest_source":"x","fields":{}}`},
		{name: "missing platform", payload: `{"ts":"2026-09-21T12:34:56Z","schema_version":"hayabusa.event.v1","ingest_source":"x","fields":{}}`},
		{name: "unsupported schema", payload: `{"ts":"2026-09-21T12:34:56Z","platform":"windows","schema_version":"hayabusa.event.v2","ingest_source":"x","fields":{}}`},
		{name: "missing source", payload: `{"ts":"2026-09-21T12:34:56Z","platform":"windows","schema_version":"hayabusa.event.v1","fields":{}}`},
		{name: "missing fields", payload: `{"ts":"2026-09-21T12:34:56Z","platform":"windows","schema_version":"hayabusa.event.v1","ingest_source":"x"}`},
		{name: "multiple json values", payload: valid + " {}"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := decodeAndValidateEvent([]byte(tc.payload))
			if err == nil {
				t.Fatalf("expected rejection")
			}
			if !isPermanentEventError(err) {
				t.Fatalf("validation error should be permanent: %T %v", err, err)
			}
		})
	}

	tooLarge := []byte(strings.Repeat("x", maxEventBytes+1))
	if _, err := decodeAndValidateEvent(tooLarge); err == nil || !isPermanentEventError(err) {
		t.Fatalf("oversized event should be a permanent error: %v", err)
	}
}

func TestStringifyMap(t *testing.T) {
	got := stringifyMap(map[string]any{
		"string": "value",
		"bool":   true,
		"number": json.Number("9007199254740993"),
		"object": map[string]any{"nested": "value"},
		"nil":    nil,
		"":       "ignored",
	})

	if got["string"] != "value" || got["bool"] != "true" || got["number"] != "9007199254740993" {
		t.Fatalf("unexpected scalar conversion: %#v", got)
	}
	if got["object"] != `{"nested":"value"}` {
		t.Fatalf("unexpected object conversion: %q", got["object"])
	}
	if _, exists := got["nil"]; exists {
		t.Fatalf("nil value should be omitted")
	}
	if _, exists := got[""]; exists {
		t.Fatalf("empty key should be omitted")
	}
}
