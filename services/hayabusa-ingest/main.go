package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	clickhouse "github.com/ClickHouse/clickhouse-go/v2"
	"github.com/ClickHouse/clickhouse-go/v2/lib/driver"
	"github.com/nats-io/nats.go"
)

const (
	supportedSchemaVersion = "hayabusa.event.v1"
	maxEventBytes          = 1 << 20
)

type permanentEventError struct { err error }

func (e permanentEventError) Error() string { return e.err.Error() }
func (e permanentEventError) Unwrap() error { return e.err }

func permanentEventErrorf(format string, args ...any) error {
	return permanentEventError{err: fmt.Errorf(format, args...)}
}

func isPermanentEventError(err error) bool {
	var target permanentEventError
	return errors.As(err, &target)
}

type eventEnvelope struct {
	TS            string         `json:"ts"`
	Platform      string         `json:"platform"`
	SchemaVersion string         `json:"schema_version"`
	IngestSource  string         `json:"ingest_source"`
	Message       string         `json:"message"`
	Fields        map[string]any `json:"fields"`
}

type config struct {
	NATSURL            string
	NATSSubject        string
	NATSStream         string
	NATSConsumer       string
	ClickHouseEndpoint string
	ClickHouseDatabase string
	ClickHouseUser     string
	ClickHousePassword string
	LogInserts         bool
}

func main() {
	cfg := config{
		NATSURL:            envOrDefault("NATS_URL", "nats://localhost:4222"),
		NATSSubject:        envOrDefault("NATS_SUBJECT", "security.events"),
		NATSStream:         envOrDefault("NATS_STREAM", "HAYABUSA_EVENTS"),
		NATSConsumer:       envOrDefault("NATS_CONSUMER", "HAYABUSA_INGEST"),
		ClickHouseEndpoint: envOrDefault("CLICKHOUSE_ENDPOINT", "http://localhost:8123"),
		ClickHouseDatabase: envOrDefault("CLICKHOUSE_DATABASE", "security"),
		ClickHouseUser:     envOrDefault("CLICKHOUSE_USER", "default"),
		ClickHousePassword: envOrDefault("CLICKHOUSE_PASSWORD", ""),
		LogInserts:         envBoolOrDefault("LOG_INSERTS", false),
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	chConn, err := connectClickHouse(ctx, cfg)
	if err != nil {
		log.Fatalf("clickhouse connection failed: %v", err)
	}

	nc, err := nats.Connect(
		cfg.NATSURL,
		nats.Name("hayabusa-ingest"),
		nats.RetryOnFailedConnect(true),
		nats.MaxReconnects(-1),
		nats.ReconnectWait(2*time.Second),
		nats.DisconnectErrHandler(func(_ *nats.Conn, err error) {
			log.Printf("nats disconnected: %v", err)
		}),
		nats.ReconnectHandler(func(conn *nats.Conn) {
			log.Printf("nats reconnected: %s", conn.ConnectedUrl())
		}),
		nats.ErrorHandler(func(_ *nats.Conn, sub *nats.Subscription, err error) {
			subject := ""
			if sub != nil {
				subject = sub.Subject
			}
			log.Printf("nats async error subject=%q: %v", subject, err)
		}),
	)
	if err != nil {
		log.Fatalf("nats connection failed: %v", err)
	}
	defer nc.Close()

	js, err := nc.JetStream()
	if err != nil {
		log.Fatalf("nats jetstream setup failed: %v", err)
	}

	sub, err := js.PullSubscribe(
		cfg.NATSSubject,
		cfg.NATSConsumer,
		nats.BindStream(cfg.NATSStream),
		nats.DeliverNew(),
		nats.ManualAck(),
	)
	if err != nil {
		log.Fatalf("nats jetstream subscribe failed stream=%q consumer=%q subject=%q: %v", cfg.NATSStream, cfg.NATSConsumer, cfg.NATSSubject, err)
	}

	log.Printf("hayabusa-ingest started nats_url=%s stream=%s consumer=%s subject=%s clickhouse_endpoint=%s database=%s", cfg.NATSURL, cfg.NATSStream, cfg.NATSConsumer, cfg.NATSSubject, cfg.ClickHouseEndpoint, cfg.ClickHouseDatabase)

	for {
		select {
		case <-ctx.Done():
			log.Println("hayabusa-ingest shutting down")
			_ = nc.Drain()
			return
		default:
			msgs, err := sub.Fetch(1, nats.MaxWait(2*time.Second))
			if err != nil {
				if errors.Is(err, nats.ErrTimeout) {
					continue
				}
				log.Printf("nats fetch failed stream=%s consumer=%s: %v", cfg.NATSStream, cfg.NATSConsumer, err)
				time.Sleep(2 * time.Second)
				continue
			}

			for _, msg := range msgs {
				if err := handleMessage(ctx, chConn, msg.Data, cfg.LogInserts); err != nil {
					if isPermanentEventError(err) {
						log.Printf("dropping invalid event subject=%s bytes=%d error=%v", msg.Subject, len(msg.Data), err)
						if termErr := msg.Term(); termErr != nil {
							log.Printf("nats term failed subject=%s error=%v", msg.Subject, termErr)
						}
						continue
					}
					log.Printf("insert failed subject=%s bytes=%d error=%v", msg.Subject, len(msg.Data), err)
					if nakErr := msg.Nak(); nakErr != nil {
						log.Printf("nats nak failed subject=%s error=%v", msg.Subject, nakErr)
					}
					continue
				}
				if ackErr := msg.Ack(); ackErr != nil {
					log.Printf("nats ack failed subject=%s error=%v", msg.Subject, ackErr)
				}
			}
		}
	}
}

func handleMessage(parent context.Context, conn driver.Conn, data []byte, logInserts bool) error {
	event, err := decodeAndValidateEvent(data)
	if err != nil {
		return err
	}

	ts, err := parseEventTime(event.TS)
	if err != nil {
		return permanentEventErrorf("invalid ts %q: %v", event.TS, err)
	}

	fields := stringifyMap(event.Fields)

	ctx, cancel := context.WithTimeout(parent, 10*time.Second)
	defer cancel()

	if err := conn.Exec(
		ctx,
		"INSERT INTO security.events (ts, platform, schema_version, ingest_source, message, fields) VALUES (?, ?, ?, ?, ?, ?)",
		ts,
		event.Platform,
		event.SchemaVersion,
		event.IngestSource,
		event.Message,
		fields,
	); err != nil {
		return err
	}

	if logInserts {
		log.Printf("inserted event ts=%s ingest_source=%s", event.TS, event.IngestSource)
	}
	return nil
}


func decodeAndValidateEvent(data []byte) (eventEnvelope, error) {
	if len(data) == 0 {
		return eventEnvelope{}, permanentEventErrorf("empty event payload")
	}
	if len(data) > maxEventBytes {
		return eventEnvelope{}, permanentEventErrorf("event payload exceeds %d bytes", maxEventBytes)
	}

	var event eventEnvelope
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	if err := decoder.Decode(&event); err != nil {
		return eventEnvelope{}, permanentEventErrorf("invalid json: %v", err)
	}
	if decoder.More() {
		return eventEnvelope{}, permanentEventErrorf("multiple JSON values in event payload")
	}
	if err := validateEvent(event); err != nil {
		return eventEnvelope{}, err
	}
	return event, nil
}

func validateEvent(event eventEnvelope) error {
	if strings.TrimSpace(event.TS) == "" {
		return permanentEventErrorf("missing ts")
	}
	if strings.TrimSpace(event.Platform) == "" {
		return permanentEventErrorf("missing platform")
	}
	if strings.TrimSpace(event.SchemaVersion) == "" {
		return permanentEventErrorf("missing schema_version")
	}
	if event.SchemaVersion != supportedSchemaVersion {
		return permanentEventErrorf("unsupported schema_version %q", event.SchemaVersion)
	}
	if strings.TrimSpace(event.IngestSource) == "" {
		return permanentEventErrorf("missing ingest_source")
	}
	if event.Fields == nil {
		return permanentEventErrorf("missing fields")
	}
	return nil
}

func connectClickHouse(parent context.Context, cfg config) (driver.Conn, error) {
	addr, secure, err := parseClickHouseEndpoint(cfg.ClickHouseEndpoint)
	if err != nil {
		return nil, err
	}

	options := &clickhouse.Options{
		Addr:     []string{addr},
		Protocol: clickhouse.HTTP,
		Auth: clickhouse.Auth{
			Database: cfg.ClickHouseDatabase,
			Username: cfg.ClickHouseUser,
			Password: cfg.ClickHousePassword,
		},
		DialTimeout: 5 * time.Second,
	}
	if secure {
		options.TLS = &tls.Config{MinVersion: tls.VersionTLS12}
	}

	conn, err := clickhouse.Open(options)
	if err != nil {
		return nil, err
	}

	ctx, cancel := context.WithTimeout(parent, 10*time.Second)
	defer cancel()
	if err := conn.Ping(ctx); err != nil {
		return nil, err
	}

	return conn, nil
}

func parseClickHouseEndpoint(endpoint string) (string, bool, error) {
	if !strings.Contains(endpoint, "://") {
		endpoint = "http://" + endpoint
	}

	parsed, err := url.Parse(endpoint)
	if err != nil {
		return "", false, err
	}
	if parsed.Host == "" {
		return "", false, fmt.Errorf("missing host in CLICKHOUSE_ENDPOINT")
	}

	switch parsed.Scheme {
	case "http":
		return parsed.Host, false, nil
	case "https":
		return parsed.Host, true, nil
	default:
		return "", false, fmt.Errorf("unsupported CLICKHOUSE_ENDPOINT scheme %q", parsed.Scheme)
	}
}

func parseEventTime(value string) (time.Time, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return time.Time{}, fmt.Errorf("empty timestamp")
	}

	layouts := []string{
		"2006-01-02 15:04:05.999",
		"2006-01-02 15:04:05.999999",
		"2006-01-02 15:04:05",
		time.RFC3339Nano,
		time.RFC3339,
	}
	for _, layout := range layouts {
		if ts, err := time.Parse(layout, value); err == nil {
			return ts.UTC(), nil
		}
	}

	return time.Time{}, fmt.Errorf("unsupported timestamp format")
}

func stringifyMap(input map[string]any) map[string]string {
	output := make(map[string]string, len(input))
	for key, value := range input {
		if key == "" || value == nil {
			continue
		}
		output[key] = stringifyValue(value)
	}
	return output
}

func stringifyValue(value any) string {
	switch v := value.(type) {
	case string:
		return v
	case bool:
		return strconv.FormatBool(v)
	case float64:
		return strconv.FormatFloat(v, 'f', -1, 64)
	case json.Number:
		return v.String()
	default:
		encoded, err := json.Marshal(v)
		if err != nil {
			return fmt.Sprint(v)
		}
		return string(encoded)
	}
}

func envOrDefault(name string, fallback string) string {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	return value
}

func envBoolOrDefault(name string, fallback bool) bool {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return fallback
	}
	return parsed
}
