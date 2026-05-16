# aweb Haskell/NATS Rewrite Implementation Plan

> **For agentic workers:** This is a single-session plan. Work through sections in order. After completing each task, check it off by editing this file — replace `- [ ]` with `- [x]` and append the git commit SHA. Example: `- [x] **Task completed** (abc1234)`. Commit the plan update alongside the implementation commit.

**Goal:** Build a parallel Haskell/Servant HTTP server with NATS messaging that implements aweb's coordination API, alongside Go CLI dual-transport support.

**Architecture:** Haskell/Servant for HTTP CRUD (tasks, workspaces, agents, roles, instructions, repos, claims, dashboard). NATS for real-time messaging (mail, chat, presence, events). PostgreSQL via rel8 for persistence. NATS JetStream for message replay. Go CLI connects to both HTTP and NATS.

**Tech Stack:** GHC 9.10, Servant, rel8, Warp, natskell, katip, optparse-applicative, aeson, ed25519, process-compose, NATS JetStream

**Reference code:**
- Scape orchestrator: `/home/ben/dev/scape/agent/` (Servant + NATS patterns)
- aweb Python server: `/home/ben/dev/aweb/server/src/aweb/` (API surface to replicate)
- aweb Go CLI: `/home/ben/dev/aweb/cli/go/` (client to extend)
- Design spec: `/home/ben/dev/aweb/docs/superpowers/specs/2026-05-16-haskell-nats-rewrite-design.md`

---

## Section 1: Project Scaffold

### Task 1.1: Create Haskell project structure

- [ ] Create `hs/` directory at repo root with cabal project:

**Files to create:**
- `hs/aweb-hs.cabal`
- `hs/cabal.project`
- `hs/app/Main.hs`
- `hs/src/Aweb/Config.hs`
- `hs/src/Aweb/Service.hs`
- `hs/src/Aweb/API.hs`

**`hs/aweb-hs.cabal`:**
```cabal
cabal-version: 3.0
name:          aweb-hs
version:       0.1.0
synopsis:      aweb coordination server (Haskell)
license:       MIT
build-type:    Simple

common shared
  default-language: GHC2021
  default-extensions:
    DataKinds
    DeriveAnyClass
    DeriveGeneric
    DerivingStrategies
    DuplicateRecordFields
    LambdaCase
    OverloadedRecordDot
    OverloadedStrings
    StrictData
    TypeFamilies
    TypeOperators
  ghc-options: -Wall -Wunused-packages

library
  import: shared
  hs-source-dirs: src
  exposed-modules:
    Aweb.API
    Aweb.Config
    Aweb.Service
  build-depends:
    base >= 4.18 && < 5,
    aeson >= 2.2,
    bytestring,
    http-types,
    katip >= 0.8,
    optparse-applicative >= 0.18,
    servant >= 0.20,
    servant-server,
    text,
    time,
    uuid,
    wai,
    warp

executable aweb-hs
  import: shared
  hs-source-dirs: app
  main-is: Main.hs
  build-depends:
    base,
    aweb-hs,
    optparse-applicative >= 0.18,
    text
```

**`hs/cabal.project`:**
```
packages: .
```

**`hs/app/Main.hs`:**
```haskell
module Main where

import Aweb.Config (parseConfig)
import Aweb.Service (runServer)

main :: IO ()
main = parseConfig >>= runServer
```

**`hs/src/Aweb/Config.hs`:**
```haskell
module Aweb.Config
  ( Config (..)
  , parseConfig
  ) where

import Data.Text (Text)
import Options.Applicative

data Config = Config
  { httpPort    :: !Int
  , databaseUrl :: !Text
  , natsUrl     :: !Text
  , awidUrl     :: !Text
  , logLevel    :: !Text
  }
  deriving stock (Show)

parseConfig :: IO Config
parseConfig = execParser opts
  where
    opts = info (configParser <**> helper)
      (fullDesc <> progDesc "aweb coordination server (Haskell)")

configParser :: Parser Config
configParser = Config
  <$> option auto
      (long "port" <> short 'p' <> value 8080 <> help "HTTP port")
  <*> strOption
      (long "database-url" <> value "postgresql://aweb:aweb@localhost:5433/aweb" <> help "PostgreSQL URL")
  <*> strOption
      (long "nats-url" <> value "nats://localhost:4222" <> help "NATS server URL")
  <*> strOption
      (long "awid-url" <> value "http://localhost:8010" <> help "awid registry URL")
  <*> strOption
      (long "log-level" <> value "info" <> help "Log level")
```

**`hs/src/Aweb/Service.hs`:**
```haskell
module Aweb.Service (runServer) where

import Aweb.API (API, server)
import Aweb.Config (Config (..))
import Data.Proxy (Proxy (..))
import Network.Wai.Handler.Warp qualified as Warp
import Servant (serve)

runServer :: Config -> IO ()
runServer cfg = do
  putStrLn $ "aweb-hs listening on port " <> show cfg.httpPort
  Warp.run cfg.httpPort (serve (Proxy @API) server)
```

**`hs/src/Aweb/API.hs`:**
```haskell
module Aweb.API (API, server) where

import Data.Aeson (ToJSON, object, (.=))
import Data.Text (Text)
import GHC.Generics (Generic)
import Servant

data HealthStatus = HealthStatus
  { status  :: Text
  , version :: Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON)

type API = "health" :> Get '[JSON] HealthStatus

server :: Server API
server = pure HealthStatus { status = "ok", version = "0.1.0" }
```

- [ ] Verify it builds: `cd hs && cabal build`
- [ ] Verify it runs: `cabal run aweb-hs -- --port 8080` then `curl http://localhost:8080/health`
- [ ] Commit: `git add hs/ && git commit -m "feat(hs): scaffold Haskell server with health endpoint"`

### Task 1.2: Add to Nix flake

- [ ] Add the Haskell package to `flake.nix`:
  - Add `aweb-hs` as a cabal2nix package using the scape pattern
  - Add to `packages.${system}`
  - Add GHC + cabal + HLS to dev shell

- [ ] Verify: `nix build .#aweb-hs`
- [ ] Commit: `git commit -m "nix: add aweb-hs Haskell package"`

---

## Section 2: Database Layer (rel8)

### Task 2.1: Add rel8 and PostgreSQL connection

- [ ] Add dependencies to `aweb-hs.cabal`: `rel8`, `hasql`, `hasql-pool`, `hasql-transaction`
- [ ] Create `hs/src/Aweb/DB.hs` — connection pool setup using hasql-pool
- [ ] Create `hs/src/Aweb/DB/Schema.hs` — rel8 table definitions for core tables

**Key tables to define (matching existing Python schema):**
- `teams` (team_id TEXT PK, namespace, team_name, team_did_key, created_at)
- `agents` (agent_id UUID PK, team_id, did_key, did_aw, address, alias, lifetime, status, created_at, deleted_at)
- `tasks` (task_id UUID PK, team_id, task_number, title, description, status, priority, assignee_alias, created_by_alias)
- `task_comments` (comment_id UUID PK, task_id, author_alias, body, created_at)
- `task_deps` (task_id, depends_on_task_id)
- `workspaces` (workspace_id UUID PK, team_id, agent_id, alias, workspace_path, hostname, last_seen_at)
- `messages` (message_id UUID PK, from_did, to_did, conversation_id, body, subject, signature, created_at, read_at)
- `conversations` (conversation_id UUID PK, conversation_type, status, created_by_did, updated_at)
- `conversation_participants` (conversation_id, did, agent_id, alias, role)
- `reservations` (team_id, resource_key PK, holder_alias, holder_agent_id, acquired_at, expires_at, metadata_json)
- `team_roles` (id UUID PK, team_id, version, bundle_json JSONB, is_active)
- `team_instructions` (id UUID PK, team_id, version, document_json JSONB, is_active)
- `repos` (repo_id UUID PK, team_id, repo_url, branch, registered_by_alias)

- [ ] Wire DB pool into `Service.hs` (initialize on startup, pass to handlers)
- [ ] Test: `cabal build` compiles, server starts and connects to PostgreSQL
- [ ] Commit: `git commit -m "feat(hs): add rel8 schema definitions and DB pool"`

### Task 2.2: Database query modules

- [ ] Create `hs/src/Aweb/DB/Agents.hs` — CRUD queries for agents table
- [ ] Create `hs/src/Aweb/DB/Tasks.hs` — CRUD queries for tasks, comments, deps
- [ ] Create `hs/src/Aweb/DB/Workspaces.hs` — CRUD queries for workspaces
- [ ] Create `hs/src/Aweb/DB/Messages.hs` — insert/query messages and conversations
- [ ] Create `hs/src/Aweb/DB/Reservations.hs` — acquire/release/list reservations
- [ ] Create `hs/src/Aweb/DB/TeamConfig.hs` — roles and instructions CRUD
- [ ] Create `hs/src/Aweb/DB/Repos.hs` — repos CRUD

Each module exports typed query functions using rel8's `select`, `insert`, `update`, `delete`. Follow the pattern:

```haskell
-- Example: DB/Agents.hs
listAgents :: TeamId -> Statement () [AgentRow]
listAgents teamId = select $ do
  agent <- each agentSchema
  where_ $ agent.teamId ==. lit teamId
  where_ $ isNull agent.deletedAt
  pure agent
```

- [ ] Commit: `git commit -m "feat(hs): add rel8 query modules for all tables"`

---

## Section 3: Auth Middleware

### Task 3.1: DID key verification

- [ ] Add dependencies: `crypton`, `memory`, `base58-bytestring`, `base64-bytestring`
- [ ] Create `hs/src/Aweb/Auth/DID.hs`:
  - `parseDIDKey :: Text -> Either Text Ed25519.PublicKey` — decode `did:key:z...` to public key
  - `computeDIDKey :: Ed25519.PublicKey -> Text` — encode public key to `did:key:z...`
  - `computeStableId :: Ed25519.PublicKey -> Text` — SHA256 → first 20 bytes → base58 → `did:aw:...`

- [ ] Create `hs/src/Aweb/Auth/Signing.hs`:
  - `canonicalJSON :: Map Text Value -> ByteString` — sorted keys, no whitespace (must match Go/Python)
  - `verifyRequestSignature :: Ed25519.PublicKey -> ByteString -> ByteString -> Bool` — verify Ed25519 sig

- [ ] Create `hs/src/Aweb/Auth/Middleware.hs`:
  - Parse `Authorization: DIDKey <did:key:z...> <signature>` header
  - Parse `X-AWEB-Timestamp` header, enforce 300s skew
  - Compute `body_sha256` from request body
  - Build canonical signing payload: `{"body_sha256":"...","did_aw":"...","timestamp":"..."}`
  - Verify signature
  - Return `IdentityAuth { didKey, didAw, address }` or 401

- [ ] Write hspec tests for DID encoding/decoding and signature verification using test vectors from the Go CLI tests
- [ ] Commit: `git commit -m "feat(hs): DID key auth middleware with Ed25519 verification"`

### Task 3.2: awid registry client

- [ ] Add dependencies: `http-client`, `http-client-tls`
- [ ] Create `hs/src/Aweb/Auth/Registry.hs`:
  - `data KeyResolution = KeyResolution { currentDIDKey :: Text }`
  - `resolveKey :: Manager -> Text -> Text -> IO (Maybe KeyResolution)` — call awid `/v1/did/{did_aw}/key`
  - Cache recent resolutions in a TVar map with TTL

- [ ] Wire into auth middleware: after verifying signature, resolve `did:aw` → `did:key` via registry, confirm match
- [ ] Commit: `git commit -m "feat(hs): awid registry client for DID resolution"`

---

## Section 4: HTTP API Endpoints

### Task 4.1: Servant API type definition

- [ ] Expand `hs/src/Aweb/API.hs` with full API type covering all endpoint groups:

```haskell
type API =
       "health" :> Get '[JSON] HealthStatus
  :<|> AuthProtect "did" :> ProtectedAPI

type ProtectedAPI =
       "v1" :> "agents" :> AgentsAPI
  :<|> "v1" :> "tasks" :> TasksAPI
  :<|> "v1" :> "workspaces" :> WorkspacesAPI
  :<|> "v1" :> "messages" :> MessagesAPI
  :<|> "v1" :> "conversations" :> ConversationsAPI
  :<|> "v1" :> "reservations" :> ReservationsAPI
  :<|> "v1" :> "roles" :> RolesAPI
  :<|> "v1" :> "instructions" :> InstructionsAPI
  :<|> "v1" :> "repos" :> ReposAPI
  :<|> "v1" :> "claims" :> ClaimsAPI
  :<|> "v1" :> "dashboard" :> DashboardAPI
  :<|> "v1" :> "connect" :> ConnectAPI
```

- [ ] Define sub-API types for each group (matching the Python route map)
- [ ] Create request/response types in `hs/src/Aweb/API/Types.hs`
- [ ] Commit: `git commit -m "feat(hs): complete Servant API type definition"`

### Task 4.2: Agents endpoints

- [ ] Create `hs/src/Aweb/Handlers/Agents.hs`:
  - `POST /v1/agents` — register agent (did_key, alias, team_id)
  - `GET /v1/agents` — list agents for team
  - `GET /v1/agents/:alias` — get agent by alias
  - `DELETE /v1/agents/:alias` — soft-delete agent
  - `GET /v1/agents/suggest-alias-prefix` — suggest alias

- [ ] Test against existing Python test patterns (seed DB, make HTTP request, verify response)
- [ ] Commit: `git commit -m "feat(hs): agents CRUD endpoints"`

### Task 4.3: Tasks endpoints

- [ ] Create `hs/src/Aweb/Handlers/Tasks.hs`:
  - `POST /v1/tasks` — create task
  - `GET /v1/tasks` — list tasks (with filters: status, assignee)
  - `GET /v1/tasks/:ref` — get task by number
  - `PATCH /v1/tasks/:ref` — update task (status, assignee, priority)
  - `DELETE /v1/tasks/:ref` — close/delete task
  - `POST /v1/tasks/:ref/comments` — add comment
  - `GET /v1/tasks/:ref/comments` — list comments
  - `POST /v1/tasks/:ref/deps` — add dependency
  - `DELETE /v1/tasks/:ref/deps/:dep_ref` — remove dependency

- [ ] Commit: `git commit -m "feat(hs): tasks CRUD with comments and dependencies"`

### Task 4.4: Workspaces endpoints

- [ ] Create `hs/src/Aweb/Handlers/Workspaces.hs`:
  - `POST /v1/workspaces` — register workspace
  - `POST /v1/workspaces/heartbeat` — workspace heartbeat (update last_seen_at)
  - `GET /v1/workspaces` — list active workspaces
  - `GET /v1/workspaces/:workspace_id` — get workspace
  - `POST /v1/workspaces/deactivate` — deactivate workspace
  - `DELETE /v1/workspaces/:workspace_id` — delete workspace

- [ ] Commit: `git commit -m "feat(hs): workspaces lifecycle endpoints"`

### Task 4.5: Messages and Conversations endpoints

- [ ] Create `hs/src/Aweb/Handlers/Messages.hs`:
  - `POST /v1/messages` — send message (persists to DB, also publishes to NATS if connected)
  - `GET /v1/messages/inbox` — get inbox for authenticated agent
  - `POST /v1/messages/:message_id/ack` — acknowledge message

- [ ] Create `hs/src/Aweb/Handlers/Conversations.hs`:
  - `POST /v1/conversations` — create conversation
  - `GET /v1/conversations/:conversation_id` — get conversation with participants

- [ ] Commit: `git commit -m "feat(hs): messages and conversations endpoints"`

### Task 4.6: Reservations (locks) endpoints

- [ ] Create `hs/src/Aweb/Handlers/Reservations.hs`:
  - `POST /v1/reservations` — acquire lock (team_id, resource_key, holder)
  - `GET /v1/reservations` — list active reservations for team
  - `POST /v1/reservations/revoke` — release lock

- [ ] Commit: `git commit -m "feat(hs): reservations (distributed locks) endpoints"`

### Task 4.7: Roles, Instructions, Repos, Claims, Dashboard

- [ ] Create `hs/src/Aweb/Handlers/Roles.hs` — CRUD + activate
- [ ] Create `hs/src/Aweb/Handlers/Instructions.hs` — CRUD + activate
- [ ] Create `hs/src/Aweb/Handlers/Repos.hs` — register, list, get
- [ ] Create `hs/src/Aweb/Handlers/Claims.hs` — claim/release slots
- [ ] Create `hs/src/Aweb/Handlers/Dashboard.hs` — team status aggregation
- [ ] Commit: `git commit -m "feat(hs): roles, instructions, repos, claims, dashboard endpoints"`

---

## Section 5: NATS Integration

### Task 5.1: NATS connection and auth callout

- [ ] Add `natskell` dependency to cabal file
- [ ] Create `hs/src/Aweb/Nats.hs`:
  - `connectNats :: Config -> IO NatsConnection`
  - Subscribe to relevant subjects on startup

- [ ] Create `hs/src/Aweb/Nats/AuthCallout.hs`:
  - Handler for NATS auth callout requests
  - Verify DID signature from connecting agent
  - Resolve identity via awid registry
  - Look up team membership in DB
  - Return scoped permissions (publish/subscribe subjects)
  - Rate limit connection attempts

- [ ] Add auth callout endpoint to Servant API: `"nats" :> "auth" :> ReqBody '[JSON] AuthCalloutRequest :> Post '[JSON] AuthCalloutResponse`
- [ ] Commit: `git commit -m "feat(hs): NATS connection and auth callout handler"`

### Task 5.2: NATS messaging subjects

- [ ] Create `hs/src/Aweb/Nats/Subjects.hs`:
  - Subject constructors for the namespace:
    - `mailSubject :: TeamId -> Alias -> Text` → `aweb.mail.<team>.<alias>`
    - `chatSubject :: TeamId -> Alias -> Text` → `agents.prompt.aweb.<team>.<alias>`
    - `presenceSubject :: TeamId -> Alias -> Text` → `agents.hb.aweb.<team>.<alias>`
    - `eventsSubject :: TeamId -> Text` → `aweb.events.<team>`

- [ ] Create `hs/src/Aweb/Nats/Publish.hs`:
  - `publishMail :: NatsConnection -> TeamId -> Alias -> Message -> IO ()`
  - `publishEvent :: NatsConnection -> TeamId -> Event -> IO ()`
  - `publishPresence :: NatsConnection -> TeamId -> Alias -> PresenceStatus -> IO ()`

- [ ] Commit: `git commit -m "feat(hs): NATS subject namespace and publishing helpers"`

### Task 5.3: JetStream persistence subscriber

- [ ] Create `hs/src/Aweb/Nats/Subscriber.hs`:
  - Subscribe to `aweb.mail.>` stream — on each message, insert into PostgreSQL `messages` table
  - Subscribe to `agents.prompt.aweb.>` — persist chat messages to `chat_messages` table
  - Subscribe to `aweb.events.>` — persist events (optional, for dashboard queries)

- [ ] Configure JetStream streams on startup (create if not exist):
  - `AWEB_MAIL`: subjects `aweb.mail.>`, retention by limits
  - `AWEB_CHAT`: subjects `agents.prompt.aweb.>`, retention by limits
  - `AWEB_EVENTS`: subjects `aweb.events.>`, retention 7 days

- [ ] Commit: `git commit -m "feat(hs): JetStream subscriber persists messages to PostgreSQL"`

### Task 5.4: Presence tracking via NATS

- [ ] Create `hs/src/Aweb/Nats/Presence.hs`:
  - Subscribe to `agents.hb.aweb.>` — track heartbeats in TVar map
  - `getOnlineAgents :: TeamId -> STM [AgentPresence]`
  - Expire agents not seen in 30s
  - Feed into workspace `last_seen_at` updates

- [ ] Wire presence data into dashboard/status endpoints
- [ ] Commit: `git commit -m "feat(hs): NATS-based presence tracking with heartbeat expiry"`

---

## Section 6: Go CLI Dual Transport

### Task 6.1: NATS client in Go CLI

- [ ] Add `nats.go` dependency to `cli/go/go.mod`
- [ ] Create `cli/go/run/nats.go`:
  - `type NatsTransport struct` — holds NATS connection
  - `ConnectNats(cfg *Config) (*NatsTransport, error)` — connect with DID-signed auth
  - Connection auth: sign challenge with agent's Ed25519 key (same key used for HTTP)
  - Read NATS URL from workspace config (`.aw/workspace.yaml` or env var `AWEB_NATS_URL`)

- [ ] Commit: `git commit -m "feat(cli): add NATS transport connection with DID auth"`

### Task 6.2: Mail over NATS

- [ ] Modify `cli/go/cmd/aw/mail_send.go` (or equivalent):
  - If NATS transport available, publish to `aweb.mail.<team>.<recipient>` subject
  - Sign message with agent's key (same signing as HTTP body)
  - Fall through to HTTP if NATS unavailable

- [ ] Modify inbox command:
  - Subscribe to `aweb.mail.<team>.<own_alias>` for real-time delivery
  - Also query HTTP `/v1/messages/inbox` for historical messages

- [ ] Commit: `git commit -m "feat(cli): mail send/inbox via NATS transport"`

### Task 6.3: Chat over NATS

- [ ] Modify chat commands:
  - `aw chat send-and-wait` → NATS request on `agents.prompt.aweb.<team>.<target>`, await reply
  - `aw chat pending` → check for pending NATS requests on own subject
  - `aw chat send-and-leave` → NATS publish (no reply expected)

- [ ] Commit: `git commit -m "feat(cli): chat send/receive via NATS request-reply"`

### Task 6.4: Presence heartbeat over NATS

- [ ] Modify workspace heartbeat:
  - Publish to `agents.hb.aweb.<team>.<alias>` on interval (every 10s)
  - Include workspace metadata in heartbeat payload (workspace_path, hostname, focus_task)

- [ ] Commit: `git commit -m "feat(cli): presence heartbeat via NATS publish"`

---

## Section 7: Dev Environment

### Task 7.1: Add NATS to process-compose

- [ ] Modify `dev/process-compose.yaml`:
  - Add `nats` process (nats-server with JetStream, port 4222, auth callout to localhost:8080)
  - Add `aweb-hs` process (Haskell server on port 8080, depends on postgres, redis, nats)
  - Keep existing `awid` and `aweb` (Python) processes for side-by-side testing

- [ ] Add `nats-server` to Nix flake dev shell packages
- [ ] Create `dev/nats-server.conf` — NATS config with:
  - JetStream enabled, store in `.data/nats/`
  - Auth callout URL pointing to Haskell server
  - Appropriate limits (max_payload, max_connections)

- [ ] Commit: `git commit -m "feat(dev): add NATS server and Haskell server to process-compose"`

### Task 7.2: NATS configuration documentation

- [ ] Create `docs/nats-configuration.md`:
  - Dev setup (process-compose, auth callout)
  - Production setup for scape integration:
    - Account creation for aweb
    - Subject permissions
    - JetStream stream definitions
    - Auth callout registration
    - Monitoring endpoints
  - Example `nats-server.conf` (standalone)
  - Example additions to scape's `nats.nix`

- [ ] Commit: `git commit -m "docs: NATS configuration guide for dev and production"`

---

## Section 8: Testing

### Task 8.1: Hspec test scaffold

- [ ] Add `hspec`, `hspec-wai`, `hspec-wai-json` to cabal test dependencies
- [ ] Create `hs/test/Spec.hs` (test entry point)
- [ ] Create `hs/test/Aweb/Auth/DIDSpec.hs` — test DID encoding/decoding against known vectors
- [ ] Create `hs/test/Aweb/Auth/SigningSpec.hs` — test canonical JSON and signature verification
- [ ] Run: `cd hs && cabal test`
- [ ] Commit: `git commit -m "test(hs): auth module hspec tests with known test vectors"`

### Task 8.2: API endpoint tests

- [ ] Create `hs/test/Aweb/API/HealthSpec.hs` — verify health endpoint
- [ ] Create `hs/test/Aweb/API/AgentsSpec.hs` — test agent CRUD (requires test DB)
- [ ] Create `hs/test/Aweb/API/TasksSpec.hs` — test tasks CRUD
- [ ] Create test fixtures: `hs/test/Fixtures.hs` — seed team, agents, provide authenticated requests
- [ ] Commit: `git commit -m "test(hs): API endpoint hspec tests with test database"`

### Task 8.3: Python conformance test adapter

- [ ] Create `hs/test/conftest_override.py` — pytest conftest that points at Haskell server:
  ```python
  @pytest.fixture
  def base_url():
      return os.environ.get("AWEB_TEST_URL", "http://localhost:8080")
  ```
- [ ] Document how to run: start Haskell server, then `cd server && AWEB_TEST_URL=http://localhost:8080 uv run pytest tests/test_*_http.py`
- [ ] Commit: `git commit -m "test: Python conformance tests can target Haskell server"`

### Task 8.4: NATS integration tests

- [ ] Create `hs/test/Aweb/Nats/AuthCalloutSpec.hs` — test auth callout accept/reject
- [ ] Create `hs/test/Aweb/Nats/MailSpec.hs` — publish mail, verify persisted to DB
- [ ] Create `hs/test/Aweb/Nats/PresenceSpec.hs` — heartbeat tracking and expiry
- [ ] Commit: `git commit -m "test(hs): NATS integration tests for auth, mail, presence"`

---

## Section 9: NixOS Module

### Task 9.1: Haskell server NixOS module

- [ ] Create `nix/modules/aweb-hs.nix`:
  - `services.aweb.hs.enable`
  - `services.aweb.hs.package` (the Haskell binary)
  - `services.aweb.hs.port` (default 8080)
  - `services.aweb.hs.databaseUrl`
  - `services.aweb.hs.natsUrl`
  - `services.aweb.hs.awidUrl`
  - systemd service with DynamicUser, ProtectSystem, NoNewPrivileges
  - After: postgresql, nats, awid

- [ ] Import from `nix/modules/default.nix`
- [ ] Commit: `git commit -m "nix: add NixOS module for aweb-hs server"`

---

## Checkpoint Summary

After completing all sections, the deliverables are:

1. **Haskell HTTP server** (`hs/`) — builds, serves all CRUD endpoints, passes auth
2. **NATS integration** — auth callout, mail/chat/presence subjects, JetStream persistence
3. **Go CLI dual transport** — NATS for messaging, HTTP for CRUD
4. **Dev environment** — process-compose runs NATS + Haskell server alongside existing Python
5. **Tests** — hspec unit/integration tests + Python conformance test adapter
6. **NixOS module** — deployable on scape infrastructure
7. **Documentation** — NATS configuration guide

The existing Python server remains fully functional throughout. The `aw` CLI works against both backends.
