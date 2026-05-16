module Aweb.Nats
  ( NatsEnv (..)
  , connectNats
  , disconnectNats
  ) where

import Aweb.Config (Config (..))
import Data.Text (Text)

-- | NATS environment (placeholder until natskell is integrated)
data NatsEnv = NatsEnv
  { natsUrl :: Text
  }

-- | Connect to NATS server
connectNats :: Config -> IO (Maybe NatsEnv)
connectNats cfg = do
  putStrLn $ "NATS: would connect to " <> show cfg.natsUrl
  pure $ Just NatsEnv { natsUrl = cfg.natsUrl }

-- | Disconnect from NATS server
disconnectNats :: Maybe NatsEnv -> IO ()
disconnectNats _ = pure ()
