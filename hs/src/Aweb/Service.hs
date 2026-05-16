module Aweb.Service
  ( runServer
  ) where

import Aweb.API (API, HealthStatus (..), ProtectedAPI, ConnectAPI)
import Aweb.API.Types (ConnectResponse (..))
import Aweb.Auth.Middleware (AuthIdentity (..), authHandler)
import Aweb.Config (Config (..))
import Aweb.DB (Pool, withPool)
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
import Network.Wai (Request)
import Network.Wai.Handler.Warp qualified as Warp
import Servant
import Servant.Server.Experimental.Auth (AuthHandler)

runServer :: Config -> IO ()
runServer cfg = withPool cfg.databaseUrl $ \pool -> do
  putStrLn $ "aweb-hs listening on port " <> show cfg.httpPort
  Warp.run cfg.httpPort (app pool)

app :: Pool -> Application
app pool = serveWithContext (Proxy @API) ctx (server pool)
  where
    ctx :: Context '[AuthHandler Request AuthIdentity]
    ctx = authHandler :. EmptyContext

server :: Pool -> Server API
server pool = healthServer :<|> protectedServer pool

healthServer :: Server ("health" :> Get '[JSON] HealthStatus)
healthServer = pure HealthStatus { status = "ok", version = "0.1.0" }

protectedServer :: Pool -> AuthIdentity -> Server ProtectedAPI
protectedServer pool identity =
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
  :<|> connectServer pool identity

connectServer :: Pool -> AuthIdentity -> Server ConnectAPI
connectServer _pool identity = pure ConnectResponse
  { agentId    = error "TODO: lookup agent"
  , alias      = ""
  , teamId     = ""
  , didKey     = identity.didKey
  , didAw      = Just identity.didAw
  , natsUrl    = Nothing
  }
