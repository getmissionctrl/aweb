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
