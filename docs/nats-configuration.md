# NATS Configuration Guide

## Development Setup

### Prerequisites
- `nats-server` (included in nix dev shell)
- Process-compose for orchestration

### Starting NATS in dev mode

NATS starts automatically with `devrun` (process-compose). Configuration at `dev/nats-server.conf`.

```bash
# Manual start
nats-server -c dev/nats-server.conf
```

Dev NATS listens on:
- `127.0.0.1:4222` — client connections
- `127.0.0.1:8222` — HTTP monitoring

### JetStream Streams

The aweb-hs server creates these streams on startup:

| Stream | Subjects | Retention | Purpose |
|--------|----------|-----------|---------|
| `AWEB_MAIL` | `aweb.mail.>` | Limits | Async mail messages |
| `AWEB_CHAT` | `agents.prompt.aweb.>` | Limits | Chat messages |
| `AWEB_EVENTS` | `aweb.events.>` | 7 days | Team events |

### Auth Callout

In development, the auth callout points to the aweb-hs server at `http://127.0.0.1:8080/nats/auth`. Agents authenticate by signing a challenge with their Ed25519 key.

## Subject Namespace

```
aweb.mail.<team_id>.<alias>          — Async mail delivery
agents.prompt.aweb.<team_id>.<alias> — Chat request-reply
agents.hb.aweb.<team_id>.<alias>     — Presence heartbeat
aweb.events.<team_id>                — Team event stream
```

## Production Setup (scape integration)

### Account Configuration

Create an aweb account in the scape NATS cluster:

```
# In scape nats.nix or nats-server.conf
accounts {
  aweb {
    jetstream: enabled
    users: [
      { user: "aweb-service", password: "$AWEB_NATS_PASS" }
    ]
  }
}
```

### Subject Permissions

The aweb service account needs:
- Publish: `aweb.>`, `agents.prompt.aweb.>`, `agents.hb.aweb.>`
- Subscribe: `aweb.>`, `agents.prompt.aweb.>`, `agents.hb.aweb.>`

Individual agents get scoped permissions via auth callout:
- Publish: `aweb.mail.<team>.<own_alias>`, `agents.hb.aweb.<team>.<own_alias>`
- Subscribe: `aweb.mail.<team>.<own_alias>`, `agents.prompt.aweb.<team>.<own_alias>`
- Request: `agents.prompt.aweb.<team>.<target_alias>` (for chat)

### JetStream Stream Definitions

```nix
# In scape nats.nix
jetstream {
  store_dir: "/var/lib/nats/jetstream"
  max_mem: 1GB
  max_file: 10GB
}
```

Streams are created programmatically by aweb-hs on startup.

### Auth Callout Registration

```
authorization {
  auth_callout {
    issuer: "aweb-production"
    auth_users: ["aweb-auth-service"]
    account: "aweb"
  }
}
```

### Monitoring

NATS exposes metrics at the HTTP monitoring port:
- `/healthz` — health check
- `/varz` — server variables
- `/connz` — connection info
- `/jsz` — JetStream stats

## Example Standalone nats-server.conf

```
listen: 0.0.0.0:4222
http_port: 8222

jetstream {
  store_dir: /var/lib/nats/jetstream
  max_mem: 512MB
  max_file: 5GB
}

authorization {
  auth_callout {
    issuer: "aweb"
    auth_users: ["aweb-auth"]
    account: "$G"
  }
}

max_payload: 1MB
max_connections: 1024
```
