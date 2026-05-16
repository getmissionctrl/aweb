module Aweb.Service
  ( runServer
  , HealthAPI
  , healthServer
  ) where

import Aweb.API (HealthStatus (..))
import Aweb.Config (Config (..))
import Network.Wai.Handler.Warp qualified as Warp
import Servant

runServer :: Config -> IO ()
runServer cfg = do
  putStrLn $ "aweb-hs listening on port " <> show cfg.httpPort
  Warp.run cfg.httpPort app
  where
    app = serve (Proxy @HealthAPI) healthServer

-- For now, only serve health endpoint until handlers are wired up
type HealthAPI = "health" :> Get '[JSON] HealthStatus

healthServer :: Server HealthAPI
healthServer = pure HealthStatus { status = "ok", version = "0.1.0" }
