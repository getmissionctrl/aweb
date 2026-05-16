package natstransport

import (
	"testing"

	"github.com/nats-io/nats.go"
)

func TestSanitizeSubjectToken(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"simple", "simple"},
		{"has.dot", "has-dot"},
		{"has/slash", "has-slash"},
		{"has space", "has-space"},
		{"  trimmed  ", "trimmed"},
		{"team:name", "team:name"}, // colons are allowed in NATS subjects
		{"complex.test/path here", "complex-test-path-here"},
	}
	for _, tt := range tests {
		got := sanitizeSubjectToken(tt.input)
		if got != tt.want {
			t.Errorf("sanitizeSubjectToken(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestMailSubject(t *testing.T) {
	got := MailSubject("app-aweb-ai:myteam", "agent1")
	want := "aweb.mail.app-aweb-ai:myteam.agent1"
	if got != want {
		t.Errorf("MailSubject() = %q, want %q", got, want)
	}
}

func TestChatSubject(t *testing.T) {
	got := ChatSubject("app-aweb-ai:myteam", "agent1")
	want := "agents.prompt.aweb.app-aweb-ai:myteam.agent1"
	if got != want {
		t.Errorf("ChatSubject() = %q, want %q", got, want)
	}
}

func TestPresenceSubject(t *testing.T) {
	got := PresenceSubject("app-aweb-ai:myteam", "agent1")
	want := "agents.hb.aweb.app-aweb-ai:myteam.agent1"
	if got != want {
		t.Errorf("PresenceSubject() = %q, want %q", got, want)
	}
}

func TestEventsSubject(t *testing.T) {
	got := EventsSubject("app-aweb-ai:myteam")
	want := "aweb.events.app-aweb-ai:myteam"
	if got != want {
		t.Errorf("EventsSubject() = %q, want %q", got, want)
	}
}

func TestConnectEmptyURL(t *testing.T) {
	transport, err := Connect(Config{URL: "", TeamID: "team", Alias: "agent"})
	if err != nil {
		t.Fatalf("Connect with empty URL should not error, got: %v", err)
	}
	if transport != nil {
		t.Fatal("Connect with empty URL should return nil transport")
	}
}

func TestConnectFromEnvEmpty(t *testing.T) {
	// Ensure AWEB_NATS_URL is unset
	t.Setenv("AWEB_NATS_URL", "")
	transport, err := ConnectFromEnv("team", "agent")
	if err != nil {
		t.Fatalf("ConnectFromEnv with empty env should not error, got: %v", err)
	}
	if transport != nil {
		t.Fatal("ConnectFromEnv with empty env should return nil transport")
	}
}

func TestNilTransportMethods(t *testing.T) {
	// All methods on a nil transport should be safe to call
	var transport *Transport

	if transport.IsConnected() {
		t.Error("nil transport should not be connected")
	}

	err := transport.PublishMail("target", &MailMessage{Body: "test"})
	if err == nil {
		t.Error("PublishMail on nil transport should error")
	}

	err = transport.PublishChat("target", &ChatMessage{Body: "test"})
	if err == nil {
		t.Error("PublishChat on nil transport should error")
	}

	err = transport.PublishHeartbeat(&HeartbeatMessage{Alias: "test"})
	if err == nil {
		t.Error("PublishHeartbeat on nil transport should error")
	}

	_, err = transport.RequestChat("target", &ChatMessage{Body: "test"})
	if err == nil {
		t.Error("RequestChat on nil transport should error")
	}

	_, err = transport.SubscribeMail(func(*MailMessage) {})
	if err == nil {
		t.Error("SubscribeMail on nil transport should error")
	}

	_, err = transport.SubscribeChat(func(*ChatMessage, *nats.Msg) {})
	if err == nil {
		t.Error("SubscribeChat on nil transport should error")
	}

	// These should not panic
	transport.Close()
	transport.StopHeartbeat()

	if transport.TeamID() != "" {
		t.Error("nil transport TeamID should be empty")
	}
	if transport.Alias() != "" {
		t.Error("nil transport Alias should be empty")
	}
	if transport.Conn() != nil {
		t.Error("nil transport Conn should be nil")
	}
}

func TestOwnSubjects(t *testing.T) {
	// Create a transport without actually connecting (test subject construction only)
	tr := &Transport{
		teamID: "app-aweb-ai:testteam",
		alias:  "worker1",
	}

	if got := tr.OwnMailSubject(); got != "aweb.mail.app-aweb-ai:testteam.worker1" {
		t.Errorf("OwnMailSubject() = %q", got)
	}
	if got := tr.OwnChatSubject(); got != "agents.prompt.aweb.app-aweb-ai:testteam.worker1" {
		t.Errorf("OwnChatSubject() = %q", got)
	}
	if got := tr.OwnPresenceSubject(); got != "agents.hb.aweb.app-aweb-ai:testteam.worker1" {
		t.Errorf("OwnPresenceSubject() = %q", got)
	}
}
