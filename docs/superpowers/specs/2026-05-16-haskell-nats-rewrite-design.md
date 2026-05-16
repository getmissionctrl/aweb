# aweb Haskell/NATS Rewrite Design

## Goal

Replace the Python aweb coordination server with a Haskell/Servant HTTP server + NATS messaging layer. The Haskell server handles CRUD operations only. Real-time messaging (mail, chat, presence, events) moves to NATS with agents connecting directly. This is a parallel implementation — the existing Python server stays fully functional.

## Architecture Overview

```
┌─────────────┐         ┌──────────────────┐         ┌───────────┐
│  aw CLI     │──HTTP──▶│  Haskell Server   │──HTTP──▶│  awid     │
│  (Go)       │         │  (Servant/rel8)   │         │  (Python) │
│             │──NATS──▶│                   │         └───────────┘
└─────────────┘         │  • Tasks          │
                        │  • Workspaces     │
┌─────────────┐         │  • Roles/Instrs   │         ┌───────────┐
│  Other      │──NATS──▶│  • Repos/Claims   │         │ PostgreSQL│
│  Agents     │         │  • Dashboard      │◀───────▶│  (rel8)   │
└─────────────┘         │  • Auth Callout   │         └───────────┘
                        └────────┬──────────┘
                                 │
                        ┌────────▼──────────┐
                        │     NATS Server    │
                        │  (JetStream)       │
                        │                    │
                        │  • Mail delivery   │
                        │  • Chat sessions   │
                        │  • Presence/HB     │
                        │  • Team events     │
                        └────────────────────┘
```

## Components

### 1. Haskell HTTP Server (Servant)

Exposes REST API for structured CRUD operations. Significantly smaller than the Python server because all real-time messaging is offloaded to NATS.

**Endpoints:**

| Group | Endpoints | Purpose |
|-------|-----------|---------|
| Tasks | CRUD, claim, deps, comments | Work item management |
| Workspaces | register, heartbeat, deactivate, delete | Workspace lifecycle |
| Agents | register, list, get, delete, suggest-alias | Agent metadata |
| Roles | CRUD, activate | Team role definitions |
| Instructions | CRUD, activate | Team instruction docs |
| Repos | register, list, get | Repository coordination |
| Claims | claim, release | Task claim slots |
| Dashboard | status, usage | Aggregation views |
| Health | /health | Liveness check |
| Auth Callout | NATS auth verification | Bridge DID→NATS permissions |

**Tech stack:**
- Servant (API definition + handlers)
- rel8 (PostgreSQL, type-safe relational queries)
- Warp (HTTP server)
- katip (structured logging)
- aeson (JSON serialization)

### 2. NATS Messaging Layer

Agents connect directly to NATS for all real-time communication. The Haskell server subscribes to relevant subjects to persist messages to PostgreSQL.

**Subject namespace:**

```
# Chat (Synadia-compatible request-reply with streaming)
agents.prompt.aweb.<team_id>.<agent_alias>

# Presence heartbeats (Synadia-compatible)
agents.hb.aweb.<team_id>.<agent_alias>

# Agent status queries (Synadia-compatible)
agents.status.aweb.<team_id>.<agent_alias>

# Mail (aweb-specific, fire-and-forget with JetStream persistence)
aweb.mail.<team_id>.<recipient_alias>

# Team-wide event broadcasts
aweb.events.<team_id>
```

**JetStream streams:**

| Stream | Subjects | Retention | Purpose |
|--------|----------|-----------|---------|
| AWEB_MAIL | `aweb.mail.>` | Limits (per-agent) | Mail delivery + replay |
| AWEB_CHAT | `agents.prompt.aweb.>` | Limits (per-session) | Chat history |
| AWEB_EVENTS | `aweb.events.>` | Time-based (7d) | Team event log |

**Persistence flow:** The Haskell server runs a NATS subscriber that consumes from these streams and writes to PostgreSQL. This gives dual persistence — JetStream for real-time replay, PostgreSQL for historical queries and dashboard aggregation.

### 3. NATS Auth Callout

Bridges aweb's DID-based identity to NATS connection permissions. Runs as a handler in the Haskell server.

**Flow:**
1. Agent connects to NATS, presents signed challenge: `{did_aw, did_key, timestamp, signature}`
2. NATS forwards to auth callout endpoint on the Haskell server
3. Haskell server verifies Ed25519 signature over the challenge
4. Resolves `did:aw` → `did:key` via awid HTTP API (cached)
5. Looks up agent's team membership in PostgreSQL
6. Returns NATS user JWT with scoped permissions:
   - Publish: `aweb.mail.<team_id>.*`, `agents.prompt.aweb.<team_id>.<own_alias>`
   - Subscribe: `aweb.mail.<team_id>.<own_alias>`, `aweb.events.<team_id>`, `agents.prompt.aweb.<team_id>.<own_alias>`
   - Heartbeat: `agents.hb.aweb.<team_id>.<own_alias>`

**Rate limiting:** Auth callout rejects agents connecting too frequently. NATS server-side limits (`max_payload`, per-account message rates) provide transport-level DOS protection.

### 4. Go CLI (`aw`) — Dual Transport

The `aw` CLI gets a NATS transport alongside existing HTTP:

| Operation | Transport | Why |
|-----------|-----------|-----|
| Mail send/inbox | NATS pub/sub | Real-time delivery, no HTTP roundtrip |
| Chat send-and-wait/pending | NATS request-reply | Streaming responses, lower latency |
| Presence heartbeat | NATS publish | Lightweight, periodic |
| Tasks CRUD | HTTP | Structured data, complex queries |
| Workspaces register/heartbeat | HTTP | Lifecycle operations |
| Roles/Instructions | HTTP | Config management |
| Work ready/active | HTTP | Query operations |

**Connection config:** The CLI reads NATS connection details from workspace config (`.aw/workspace.yaml`). Auth uses the agent's existing Ed25519 key to sign the NATS connection challenge — no NKey files or `nsc` needed.

**Fallback:** If NATS is unavailable, messaging operations fail with a clear error. No silent fallback to HTTP for messaging (keeps the architecture clean).

### 5. awid (unchanged)

Stays Python. Consumed over HTTP by:
- Haskell server's auth callout (DID resolution, team membership)
- Haskell server's HTTP auth middleware (same DID signing as today)

No changes needed to awid.

### 6. PostgreSQL Schema

Compatible with the existing aweb schema where possible. New tables for NATS-specific state:

| Table | Purpose | Notes |
|-------|---------|-------|
| `teams` | Team metadata | Existing |
| `agents` | Agent registry | Existing |
| `workspaces` | Workspace state | Existing |
| `tasks` | Work items | Existing |
| `task_comments` | Task comments | Existing |
| `task_deps` | Task dependencies | Existing |
| `messages` | Mail history | Existing (populated from JetStream consumer) |
| `conversations` | Chat sessions | Existing |
| `chat_messages` | Chat history | Existing (populated from JetStream consumer) |
| `reservations` | Distributed locks | Existing |
| `team_roles` | Role definitions | Existing |
| `team_instructions` | Instruction docs | Existing |
| `repos` | Repository tracking | Existing |
| `nats_connections` | Active NATS sessions | New — tracks connected agents |

## Development Environment

### process-compose additions

The existing `dev/process-compose.yaml` gets a NATS server process:

```yaml
nats:
  command: |
    mkdir -p .data/nats
    exec nats-server \
      --port 4222 \
      --jetstream \
      --store_dir .data/nats \
      --auth_callout_url http://127.0.0.1:8080/nats/auth
  readiness_probe:
    exec:
      command: nats-server --signal check --pid .data/nats/nats.pid
```

The Haskell server runs alongside (port 8080) and handles both HTTP API requests and NATS auth callouts.

### Nix flake additions

- `natskell` input (NATS Haskell client)
- Haskell package build (cabal2nix)
- NATS server in dev shell packages
- Updated NixOS module for the Haskell server

## Testing Strategy

### 1. API conformance (reuse existing Python tests)

The existing `server/tests/test_*_http.py` files (13 files, ~13K LOC) make plain HTTP requests. Adapt `conftest.py` to point at the Haskell server instead of ASGI transport:

```python
# conftest.py override
@pytest.fixture
def base_url():
    return "http://localhost:8080"  # Haskell server
```

This validates that the Haskell HTTP API is wire-compatible with the Python one.

### 2. NATS messaging tests (new, Haskell)

hspec tests that:
- Connect to NATS with a signed challenge
- Publish mail to `aweb.mail.<team>.<agent>`
- Verify message appears in PostgreSQL
- Verify JetStream replay works
- Test chat request-reply flow
- Test presence heartbeat tracking
- Test auth callout rejects invalid signatures

### 3. CLI integration tests (existing + new)

- Existing `make test-cli` validates HTTP operations still work
- New tests for NATS transport: `aw mail send` via NATS, `aw chat send-and-wait` via NATS
- e2e script (`scripts/e2e-oss-user-journey.sh`) validates full journeys once both transports wired

### 4. Auth callout tests

- Valid DID signature → connection accepted with correct permissions
- Invalid signature → connection rejected
- Revoked agent → connection rejected
- Rate limiting → rapid reconnects rejected

## NATS Configuration Documentation

The spec deliverable includes comprehensive documentation for production NATS configuration:

- Account setup (aweb account with appropriate limits)
- Auth callout configuration (URL, signing key, timeout)
- JetStream stream definitions (subjects, retention, replicas)
- Per-agent permission templates
- Monitoring and alerting (connection counts, message rates)
- Example `nats-server.conf` for both standalone and scape-integrated deployment

## Deployment

### NixOS module

New module `nix/modules/aweb-hs.nix`:
- systemd service for the Haskell binary
- Depends on NATS, PostgreSQL
- Configures NATS auth callout URL
- Environment: database URL, NATS URL, awid URL

### scape integration

Uses scape's existing NATS infrastructure:
- aweb gets its own NATS account (subject-isolated from scape orchestration)
- Auth callout registered in NATS server config
- JetStream streams provisioned on first boot

## Scope Boundaries

**In scope:**
- Haskell HTTP server (tasks, workspaces, roles, repos, dashboard, claims, agents, health)
- NATS auth callout
- NATS message persistence subscriber (→ PostgreSQL)
- Go CLI dual transport (NATS for messaging, HTTP for CRUD)
- Dev environment with NATS
- NixOS module
- Production NATS configuration docs
- API conformance testing against existing Python test suite

**Out of scope:**
- MCP tool layer (follow-up — use Haskell MCP library later)
- awid changes
- Python server modifications
- Synadia SDK interop (nice-to-have, not required)
- Migration tooling (parallel implementation, no migration needed)

## Estimated Size

| Component | Estimated Haskell LOC |
|-----------|-----------------------|
| Servant API + handlers (~30 endpoints) | ~1,500 |
| rel8 schema + queries | ~800 |
| NATS auth callout | ~300 |
| NATS subscriber (persistence) | ~400 |
| NATS subject routing + helpers | ~300 |
| awid HTTP client | ~200 |
| Server bootstrap + config | ~200 |
| **Total Haskell** | **~3,700** |
| Go CLI NATS transport | ~800 |
| **Grand total** | **~4,500** |
