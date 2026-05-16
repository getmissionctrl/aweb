// Package natstransport provides NATS-based messaging for the aweb CLI.
//
// # Subject Namespace
//
// The NATS subject hierarchy:
//
//   - Mail:     aweb.mail.<team_id>.<alias>
//   - Chat:     agents.prompt.aweb.<team_id>.<alias>
//   - Presence: agents.hb.aweb.<team_id>.<alias>
//   - Events:   aweb.events.<team_id>
//
// # Usage
//
// The transport is opt-in. Set the AWEB_NATS_URL environment variable to enable:
//
//	export AWEB_NATS_URL=nats://localhost:4222
//
// When not configured, ConnectFromEnv returns (nil, nil) and callers fall back
// to the HTTP transport.
//
// # Integration Pattern
//
//	transport, err := natstransport.ConnectFromEnv(teamID, alias)
//	if err != nil {
//	    // NATS configured but connection failed; log and fall back to HTTP
//	    log.Printf("NATS unavailable: %v", err)
//	}
//	if transport != nil {
//	    defer transport.Close()
//	    // Use NATS for messaging
//	    err = transport.PublishMail("recipient", &natstransport.MailMessage{...})
//	}
//	// Fall back to HTTP if transport is nil
package natstransport
