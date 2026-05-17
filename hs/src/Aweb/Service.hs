module Aweb.Service
  ( runServer
  ) where

import Aweb.API (API, HealthStatus (..), ProtectedAPI, ConnectAPI)
import Aweb.API.Types (ConnectResponse (..))
import Aweb.Auth.Middleware (AuthIdentity (..), authHandler)
import Aweb.Auth.Registry (newRegistryManager)
import Aweb.Config (Config (..))
import Aweb.DB (Pool, withPool, runMigrations)
import Aweb.Handlers.Agents (agentsServer)
import Aweb.Handlers.Claims (claimsServer)
import Aweb.Handlers.Conversations (conversationsServer)
import Aweb.Handlers.Dashboard (dashboardServer)
import Aweb.Handlers.Instructions (instructionsServer)
import Aweb.Handlers.Messages (messagesServer)
import Aweb.Handlers.Repos (reposServer)
import Aweb.Handlers.Reservations (reservationsServer)
import Aweb.Handlers.Roles (rolesServer)
import Aweb.Handlers.Tasks (tasksServer)
import Aweb.Handlers.Workspaces (workspacesServer)
import Aweb.Nats (NatsEnv, connectNats, disconnectNats)
import Aweb.Nats.Presence (PresenceTracker, newPresenceTracker)
import Aweb.Nats.Subscriber qualified as Sub
import Control.Exception (bracket)
import Data.UUID qualified
import Network.HTTP.Client (Manager)
import Network.Wai (Request)
import Network.Wai.Handler.Warp qualified as Warp
import Servant
import Servant.Server.Experimental.Auth (AuthHandler)

runServer :: Config -> IO ()
runServer cfg = withPool cfg.databaseUrl $ \pool -> do
  runMigrations pool ["hs/migrations/001_initial.sql"]
  registryMgr <- newRegistryManager
  tracker <- newPresenceTracker
  bracket (connectNats cfg) cleanupNats $ \mNats -> do
    case mNats of
      Nothing -> putStrLn "NATS: running without NATS (HTTP only)"
      Just nats -> do
        _subs <- Sub.startSubscribers nats tracker
        pure ()
    putStrLn $ "aweb-hs listening on port " <> show cfg.httpPort
    Warp.run cfg.httpPort (app pool mNats cfg registryMgr)
  where
    cleanupNats mNats = do
      disconnectNats mNats
      putStrLn "NATS: disconnected"

app :: Pool -> Maybe NatsEnv -> Config -> Manager -> Application
app pool _mNats cfg mgr = serveWithContext (Proxy @API) ctx (server pool _mNats cfg)
  where
    ctx :: Context '[AuthHandler Request AuthIdentity]
    ctx = authHandler mgr cfg.awidUrl :. EmptyContext

server :: Pool -> Maybe NatsEnv -> Config -> Server API
server pool mNats cfg = healthServer :<|> protectedServer pool mNats cfg

healthServer :: Server ("health" :> Get '[JSON] HealthStatus)
healthServer = pure HealthStatus { status = "ok", version = "0.1.0" }

protectedServer :: Pool -> Maybe NatsEnv -> Config -> AuthIdentity -> Server ProtectedAPI
protectedServer pool _mNats cfg identity =
       agentsServer pool identity
  :<|> tasksServer pool identity
  :<|> workspacesServer pool identity
  :<|> messagesServer pool identity
  :<|> conversationsServer pool identity
  :<|> reservationsServer pool identity
  :<|> rolesServer pool identity
  :<|> instructionsServer pool identity
  :<|> reposServer pool identity
  :<|> claimsServer pool identity
  :<|> dashboardServer pool identity
  :<|> connectServer cfg identity

connectServer :: Config -> AuthIdentity -> Server ConnectAPI
connectServer cfg identity = pure ConnectResponse
  { agentId    = Data.UUID.nil
  , alias      = ""
  , teamId     = ""
  , didKey     = identity.didKey
  , didAw      = Just identity.didAw
  , natsUrl    = Just cfg.natsUrl
  }
