// Package e2e contains end-to-end tests that require live services.
//
// Run with:
//
//	AWEB_NATS_URL=nats://localhost:4222 go test ./e2e/ -v -count=1
//
// Requires: nats-server running on localhost:4222 with JetStream enabled.
// Start dev services: devrun (from repo root)
package e2e

import (
	"encoding/json"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/awebai/aw/natstransport"
	"github.com/nats-io/nats.go"
)

func natsURL(t *testing.T) string {
	t.Helper()
	url := os.Getenv("AWEB_NATS_URL")
	if url == "" {
		t.Skip("AWEB_NATS_URL not set — skipping e2e test (start devrun first)")
	}
	return url
}

func TestNATSMailRoundTrip(t *testing.T) {
	url := natsURL(t)

	// Connect a raw subscriber to the recipient's mail subject.
	nc, err := nats.Connect(url)
	if err != nil {
		t.Fatalf("nats connect: %v", err)
	}
	defer nc.Close()

	subject := natstransport.MailSubject("e2e-test", "recipient")

	var received natstransport.MailMessage
	var wg sync.WaitGroup
	wg.Add(1)
	sub, err := nc.Subscribe(subject, func(msg *nats.Msg) {
		_ = json.Unmarshal(msg.Data, &received)
		wg.Done()
	})
	if err != nil {
		t.Fatalf("subscribe: %v", err)
	}
	defer sub.Unsubscribe()
	_ = nc.Flush()

	// Connect via natstransport and publish mail.
	transport, err := natstransport.Connect(natstransport.Config{
		URL:    url,
		TeamID: "e2e-test",
		Alias:  "sender",
	})
	if err != nil {
		t.Fatalf("transport connect: %v", err)
	}
	defer transport.Close()

	sent := &natstransport.MailMessage{
		From:      "sender",
		To:        "recipient",
		Subject:   "e2e test",
		Body:      "hello from e2e",
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}
	if err := transport.PublishMail("recipient", sent); err != nil {
		t.Fatalf("publish mail: %v", err)
	}

	// Wait for the subscriber to receive it.
	done := make(chan struct{})
	go func() { wg.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for mail message")
	}

	if received.From != "sender" {
		t.Errorf("from: got %q, want %q", received.From, "sender")
	}
	if received.To != "recipient" {
		t.Errorf("to: got %q, want %q", received.To, "recipient")
	}
	if received.Body != "hello from e2e" {
		t.Errorf("body: got %q, want %q", received.Body, "hello from e2e")
	}
}

func TestNATSHeartbeatRoundTrip(t *testing.T) {
	url := natsURL(t)

	nc, err := nats.Connect(url)
	if err != nil {
		t.Fatalf("nats connect: %v", err)
	}
	defer nc.Close()

	subject := natstransport.PresenceSubject("e2e-test", "agent1")

	var received natstransport.HeartbeatMessage
	var wg sync.WaitGroup
	wg.Add(1)
	sub, err := nc.Subscribe(subject, func(msg *nats.Msg) {
		_ = json.Unmarshal(msg.Data, &received)
		wg.Done()
	})
	if err != nil {
		t.Fatalf("subscribe: %v", err)
	}
	defer sub.Unsubscribe()
	_ = nc.Flush()

	transport, err := natstransport.Connect(natstransport.Config{
		URL:    url,
		TeamID: "e2e-test",
		Alias:  "agent1",
	})
	if err != nil {
		t.Fatalf("transport connect: %v", err)
	}
	defer transport.Close()

	hb := &natstransport.HeartbeatMessage{
		Alias:    "agent1",
		TeamID:   "e2e-test",
		Hostname: "test-host",
	}
	if err := transport.PublishHeartbeat(hb); err != nil {
		t.Fatalf("publish heartbeat: %v", err)
	}

	done := make(chan struct{})
	go func() { wg.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for heartbeat message")
	}

	if received.Alias != "agent1" {
		t.Errorf("alias: got %q, want %q", received.Alias, "agent1")
	}
	if received.TeamID != "e2e-test" {
		t.Errorf("team_id: got %q, want %q", received.TeamID, "e2e-test")
	}
	if received.Hostname != "test-host" {
		t.Errorf("hostname: got %q, want %q", received.Hostname, "test-host")
	}
	if received.Timestamp == "" {
		t.Error("timestamp should be set automatically")
	}
}

func TestNATSChatRoundTrip(t *testing.T) {
	url := natsURL(t)

	// Set up a responder that echoes back.
	responder, err := natstransport.Connect(natstransport.Config{
		URL:    url,
		TeamID: "e2e-test",
		Alias:  "responder",
	})
	if err != nil {
		t.Fatalf("responder connect: %v", err)
	}
	defer responder.Close()

	sub, err := responder.SubscribeChat(func(msg *natstransport.ChatMessage, raw *nats.Msg) {
		reply := &natstransport.ChatMessage{
			From: "responder",
			Body: "echo: " + msg.Body,
		}
		_ = natstransport.ReplyChat(raw, reply)
	})
	if err != nil {
		t.Fatalf("subscribe chat: %v", err)
	}
	defer sub.Unsubscribe()

	// Requester sends and waits for reply.
	requester, err := natstransport.Connect(natstransport.Config{
		URL:            url,
		TeamID:         "e2e-test",
		Alias:          "requester",
		RequestTimeout: 5 * time.Second,
	})
	if err != nil {
		t.Fatalf("requester connect: %v", err)
	}
	defer requester.Close()

	reply, err := requester.RequestChat("responder", &natstransport.ChatMessage{
		From: "requester",
		Body: "ping",
	})
	if err != nil {
		t.Fatalf("request chat: %v", err)
	}

	if reply.Body != "echo: ping" {
		t.Errorf("reply body: got %q, want %q", reply.Body, "echo: ping")
	}
}
