// Package natstransport provides a NATS-based transport layer for the aweb CLI.
// It supports mail delivery, chat messaging, and presence heartbeats over NATS
// subjects. The transport is opt-in: it activates only when a NATS URL is
// configured via the AWEB_NATS_URL environment variable or explicit config.
// When NATS is unavailable, the CLI falls back to HTTP seamlessly.
package natstransport

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/nats-io/nats.go"
)

// Subject namespace constants.
const (
	// SubjectMailPrefix is the prefix for mail delivery subjects.
	// Full subject: aweb.mail.<team_id>.<alias>
	SubjectMailPrefix = "aweb.mail"

	// SubjectChatPrefix is the prefix for chat prompt subjects.
	// Full subject: agents.prompt.aweb.<team_id>.<alias>
	SubjectChatPrefix = "agents.prompt.aweb"

	// SubjectPresencePrefix is the prefix for presence heartbeat subjects.
	// Full subject: agents.hb.aweb.<team_id>.<alias>
	SubjectPresencePrefix = "agents.hb.aweb"

	// SubjectEventsPrefix is the prefix for team event subjects.
	// Full subject: aweb.events.<team_id>
	SubjectEventsPrefix = "aweb.events"
)

// DefaultConnectTimeout is the timeout for establishing a NATS connection.
const DefaultConnectTimeout = 5 * time.Second

// DefaultRequestTimeout is the timeout for NATS request/reply operations.
const DefaultRequestTimeout = 30 * time.Second

// DefaultHeartbeatInterval is how often presence heartbeats are published.
const DefaultHeartbeatInterval = 10 * time.Second

// Config holds the configuration for a NATS transport connection.
type Config struct {
	// URL is the NATS server URL (e.g., "nats://localhost:4222").
	// If empty, the transport is disabled.
	URL string

	// TeamID is the team identifier used in subject construction.
	TeamID string

	// Alias is the agent's alias within the team.
	Alias string

	// ConnectTimeout overrides the default connection timeout.
	ConnectTimeout time.Duration

	// RequestTimeout overrides the default request/reply timeout.
	RequestTimeout time.Duration
}

// Transport wraps a NATS connection for aweb messaging.
type Transport struct {
	conn           *nats.Conn
	teamID         string
	alias          string
	requestTimeout time.Duration

	// heartbeat state
	mu        sync.Mutex
	hbCancel  context.CancelFunc
	hbRunning bool
}

// MailMessage represents a mail message sent over NATS.
type MailMessage struct {
	MessageID      string `json:"message_id,omitempty"`
	From           string `json:"from"`
	To             string `json:"to"`
	Subject        string `json:"subject,omitempty"`
	Body           string `json:"body"`
	Priority       string `json:"priority,omitempty"`
	ConversationID string `json:"conversation_id,omitempty"`
	Timestamp      string `json:"timestamp,omitempty"`
	FromDID        string `json:"from_did,omitempty"`
	ToDID          string `json:"to_did,omitempty"`
	FromStableID   string `json:"from_stable_id,omitempty"`
	ToStableID     string `json:"to_stable_id,omitempty"`
	Signature      string `json:"signature,omitempty"`
	SignedPayload  string `json:"signed_payload,omitempty"`
}

// ChatMessage represents a chat message sent over NATS.
type ChatMessage struct {
	MessageID      string `json:"message_id,omitempty"`
	SessionID      string `json:"session_id,omitempty"`
	From           string `json:"from"`
	To             string `json:"to,omitempty"`
	Body           string `json:"body"`
	Leaving        bool   `json:"leaving,omitempty"`
	ReplyTo        string `json:"reply_to,omitempty"`
	Timestamp      string `json:"timestamp,omitempty"`
	FromDID        string `json:"from_did,omitempty"`
	Signature      string `json:"signature,omitempty"`
	SignedPayload  string `json:"signed_payload,omitempty"`
}

// HeartbeatMessage represents a presence heartbeat published over NATS.
type HeartbeatMessage struct {
	Alias         string `json:"alias"`
	TeamID        string `json:"team_id"`
	Hostname      string `json:"hostname,omitempty"`
	WorkspacePath string `json:"workspace_path,omitempty"`
	FocusTask     string `json:"focus_task,omitempty"`
	Timestamp     string `json:"timestamp"`
	Status        string `json:"status,omitempty"`
}

// Connect establishes a NATS connection using the provided config.
// Returns nil, nil if the NATS URL is empty (transport disabled).
// Returns nil, error if the URL is configured but connection fails.
func Connect(cfg Config) (*Transport, error) {
	url := strings.TrimSpace(cfg.URL)
	if url == "" {
		return nil, nil
	}

	connectTimeout := cfg.ConnectTimeout
	if connectTimeout == 0 {
		connectTimeout = DefaultConnectTimeout
	}
	requestTimeout := cfg.RequestTimeout
	if requestTimeout == 0 {
		requestTimeout = DefaultRequestTimeout
	}

	opts := []nats.Option{
		nats.Timeout(connectTimeout),
		nats.Name(fmt.Sprintf("aweb-cli/%s/%s", cfg.TeamID, cfg.Alias)),
		nats.ReconnectWait(2 * time.Second),
		nats.MaxReconnects(-1), // Reconnect indefinitely
	}

	nc, err := nats.Connect(url, opts...)
	if err != nil {
		return nil, fmt.Errorf("nats connect: %w", err)
	}

	return &Transport{
		conn:           nc,
		teamID:         cfg.TeamID,
		alias:          cfg.Alias,
		requestTimeout: requestTimeout,
	}, nil
}

// ConnectFromEnv creates a NATS transport using environment variables and
// the provided team/alias context. Returns nil, nil if AWEB_NATS_URL is not set.
func ConnectFromEnv(teamID, alias string) (*Transport, error) {
	url := strings.TrimSpace(os.Getenv("AWEB_NATS_URL"))
	if url == "" {
		return nil, nil
	}
	return Connect(Config{
		URL:    url,
		TeamID: teamID,
		Alias:  alias,
	})
}

// Close shuts down the NATS connection and stops any running heartbeat.
func (t *Transport) Close() {
	if t == nil {
		return
	}
	t.StopHeartbeat()
	if t.conn != nil {
		t.conn.Close()
	}
}

// IsConnected returns true if the NATS connection is active.
func (t *Transport) IsConnected() bool {
	if t == nil || t.conn == nil {
		return false
	}
	return t.conn.IsConnected()
}

// --- Subject construction ---

// MailSubject returns the NATS subject for delivering mail to a recipient.
func MailSubject(teamID, recipientAlias string) string {
	return SubjectMailPrefix + "." + sanitizeSubjectToken(teamID) + "." + sanitizeSubjectToken(recipientAlias)
}

// ChatSubject returns the NATS subject for sending chat prompts to a target.
func ChatSubject(teamID, targetAlias string) string {
	return SubjectChatPrefix + "." + sanitizeSubjectToken(teamID) + "." + sanitizeSubjectToken(targetAlias)
}

// PresenceSubject returns the NATS subject for publishing presence heartbeats.
func PresenceSubject(teamID, alias string) string {
	return SubjectPresencePrefix + "." + sanitizeSubjectToken(teamID) + "." + sanitizeSubjectToken(alias)
}

// EventsSubject returns the NATS subject for team-wide events.
func EventsSubject(teamID string) string {
	return SubjectEventsPrefix + "." + sanitizeSubjectToken(teamID)
}

// OwnMailSubject returns this transport's own mail subject.
func (t *Transport) OwnMailSubject() string {
	return MailSubject(t.teamID, t.alias)
}

// OwnChatSubject returns this transport's own chat subject.
func (t *Transport) OwnChatSubject() string {
	return ChatSubject(t.teamID, t.alias)
}

// OwnPresenceSubject returns this transport's own presence subject.
func (t *Transport) OwnPresenceSubject() string {
	return PresenceSubject(t.teamID, t.alias)
}

// --- Mail operations ---

// PublishMail publishes a mail message to the recipient's mail subject.
func (t *Transport) PublishMail(recipientAlias string, msg *MailMessage) error {
	if t == nil || !t.IsConnected() {
		return fmt.Errorf("nats: not connected")
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("nats: marshal mail: %w", err)
	}
	subject := MailSubject(t.teamID, recipientAlias)
	return t.conn.Publish(subject, data)
}

// SubscribeMail subscribes to incoming mail on this agent's mail subject.
// The returned subscription can be used to receive messages or unsubscribe.
func (t *Transport) SubscribeMail(handler func(*MailMessage)) (*nats.Subscription, error) {
	if t == nil || !t.IsConnected() {
		return nil, fmt.Errorf("nats: not connected")
	}
	subject := t.OwnMailSubject()
	return t.conn.Subscribe(subject, func(msg *nats.Msg) {
		var mail MailMessage
		if err := json.Unmarshal(msg.Data, &mail); err != nil {
			return // silently drop malformed messages
		}
		handler(&mail)
	})
}

// --- Chat operations ---

// RequestChat sends a chat message and waits for a reply (request/reply pattern).
// This implements the "send-and-wait" behavior over NATS.
func (t *Transport) RequestChat(targetAlias string, msg *ChatMessage) (*ChatMessage, error) {
	if t == nil || !t.IsConnected() {
		return nil, fmt.Errorf("nats: not connected")
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return nil, fmt.Errorf("nats: marshal chat: %w", err)
	}
	subject := ChatSubject(t.teamID, targetAlias)
	reply, err := t.conn.Request(subject, data, t.requestTimeout)
	if err != nil {
		return nil, fmt.Errorf("nats: chat request to %s: %w", targetAlias, err)
	}
	var response ChatMessage
	if err := json.Unmarshal(reply.Data, &response); err != nil {
		return nil, fmt.Errorf("nats: unmarshal chat reply: %w", err)
	}
	return &response, nil
}

// PublishChat publishes a chat message without waiting for a reply.
// This implements the "send-and-leave" behavior over NATS.
func (t *Transport) PublishChat(targetAlias string, msg *ChatMessage) error {
	if t == nil || !t.IsConnected() {
		return fmt.Errorf("nats: not connected")
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("nats: marshal chat: %w", err)
	}
	subject := ChatSubject(t.teamID, targetAlias)
	return t.conn.Publish(subject, data)
}

// SubscribeChat subscribes to incoming chat messages on this agent's chat subject.
// The handler receives the message and the nats.Msg for reply capabilities.
func (t *Transport) SubscribeChat(handler func(*ChatMessage, *nats.Msg)) (*nats.Subscription, error) {
	if t == nil || !t.IsConnected() {
		return nil, fmt.Errorf("nats: not connected")
	}
	subject := t.OwnChatSubject()
	return t.conn.Subscribe(subject, func(msg *nats.Msg) {
		var chat ChatMessage
		if err := json.Unmarshal(msg.Data, &chat); err != nil {
			return // silently drop malformed messages
		}
		handler(&chat, msg)
	})
}

// ReplyChat sends a reply to a chat request (completing the request/reply pattern).
func ReplyChat(originalMsg *nats.Msg, reply *ChatMessage) error {
	if originalMsg == nil || originalMsg.Reply == "" {
		return fmt.Errorf("nats: no reply subject")
	}
	data, err := json.Marshal(reply)
	if err != nil {
		return fmt.Errorf("nats: marshal chat reply: %w", err)
	}
	return originalMsg.Respond(data)
}

// --- Presence/Heartbeat operations ---

// PublishHeartbeat publishes a single presence heartbeat.
func (t *Transport) PublishHeartbeat(msg *HeartbeatMessage) error {
	if t == nil || !t.IsConnected() {
		return fmt.Errorf("nats: not connected")
	}
	if msg.Timestamp == "" {
		msg.Timestamp = time.Now().UTC().Format(time.RFC3339)
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("nats: marshal heartbeat: %w", err)
	}
	subject := t.OwnPresenceSubject()
	return t.conn.Publish(subject, data)
}

// StartHeartbeat begins periodic heartbeat publishing in the background.
// It stops when ctx is cancelled or StopHeartbeat is called.
func (t *Transport) StartHeartbeat(ctx context.Context, meta *HeartbeatMessage) {
	if t == nil || !t.IsConnected() {
		return
	}

	t.mu.Lock()
	if t.hbRunning {
		t.mu.Unlock()
		return
	}
	hbCtx, cancel := context.WithCancel(ctx)
	t.hbCancel = cancel
	t.hbRunning = true
	t.mu.Unlock()

	go func() {
		ticker := time.NewTicker(DefaultHeartbeatInterval)
		defer ticker.Stop()
		defer func() {
			t.mu.Lock()
			t.hbRunning = false
			t.mu.Unlock()
		}()

		// Publish immediately on start
		hb := *meta
		hb.Timestamp = time.Now().UTC().Format(time.RFC3339)
		_ = t.PublishHeartbeat(&hb)

		for {
			select {
			case <-hbCtx.Done():
				return
			case <-ticker.C:
				hb := *meta
				hb.Timestamp = time.Now().UTC().Format(time.RFC3339)
				_ = t.PublishHeartbeat(&hb)
			}
		}
	}()
}

// StopHeartbeat stops the background heartbeat goroutine.
func (t *Transport) StopHeartbeat() {
	if t == nil {
		return
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.hbCancel != nil {
		t.hbCancel()
		t.hbCancel = nil
	}
}

// --- Event subscription ---

// SubscribeEvents subscribes to team-wide events.
func (t *Transport) SubscribeEvents(handler func([]byte)) (*nats.Subscription, error) {
	if t == nil || !t.IsConnected() {
		return nil, fmt.Errorf("nats: not connected")
	}
	subject := EventsSubject(t.teamID)
	return t.conn.Subscribe(subject, func(msg *nats.Msg) {
		handler(msg.Data)
	})
}

// --- Helpers ---

// sanitizeSubjectToken replaces characters that are invalid in NATS subjects.
// NATS subjects use dots as delimiters; colons and slashes in team IDs and
// aliases are replaced with dashes.
func sanitizeSubjectToken(token string) string {
	token = strings.TrimSpace(token)
	token = strings.ReplaceAll(token, ".", "-")
	token = strings.ReplaceAll(token, "/", "-")
	token = strings.ReplaceAll(token, " ", "-")
	return token
}

// Conn returns the underlying NATS connection for advanced usage.
// Returns nil if the transport is nil or not connected.
func (t *Transport) Conn() *nats.Conn {
	if t == nil {
		return nil
	}
	return t.conn
}

// TeamID returns the configured team ID.
func (t *Transport) TeamID() string {
	if t == nil {
		return ""
	}
	return t.teamID
}

// Alias returns the configured agent alias.
func (t *Transport) Alias() string {
	if t == nil {
		return ""
	}
	return t.alias
}
