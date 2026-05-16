module Aweb.Nats.Subscriber
  ( startSubscribers
  , stopSubscribers
  ) where

import Aweb.Nats (NatsEnv (..))

-- | Start JetStream subscribers that persist messages to PostgreSQL
startSubscribers :: NatsEnv -> IO ()
startSubscribers _env = do
  putStrLn "NATS subscribers: would start JetStream consumers"
  pure ()

-- | Stop all active subscribers
stopSubscribers :: IO ()
stopSubscribers = pure ()
