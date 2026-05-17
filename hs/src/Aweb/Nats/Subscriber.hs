module Aweb.Nats.Subscriber
  ( Subscriptions
  , startSubscribers
  , stopSubscribers
  ) where

import Aweb.Nats (NatsEnv (..))
import Aweb.Nats.Presence (PresenceTracker, trackHeartbeat)
import Client qualified as Nats
import Data.Aeson (FromJSON (..), eitherDecodeStrict, withObject, (.:), (.:?))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import GHC.Generics (Generic)

-- | Heartbeat message received from NATS.
data HeartbeatMsg = HeartbeatMsg
  { alias         :: Text
  , teamId        :: Text
  , hostname      :: Maybe Text
  , workspacePath :: Maybe Text
  , focusTask     :: Maybe Text
  }
  deriving stock (Generic)

instance FromJSON HeartbeatMsg where
  parseJSON = withObject "HeartbeatMsg" $ \v -> HeartbeatMsg
    <$> v .: "alias"
    <*> v .: "team_id"
    <*> v .:? "hostname"
    <*> v .:? "workspace_path"
    <*> v .:? "focus_task"

-- | Opaque handle for active subscriptions.
newtype Subscriptions = Subscriptions [ByteString]

-- | Start NATS subscribers for presence tracking.
startSubscribers :: NatsEnv -> PresenceTracker -> IO Subscriptions
startSubscribers env tracker = do
  -- Subscribe to presence heartbeats: agents.hb.aweb.>
  hbSid <- Nats.subscribe env.client "agents.hb.aweb.>" $ \msg ->
    case Nats.payload msg >>= parseHeartbeat of
      Just hb -> trackHeartbeat tracker hb.teamId hb.alias hb.hostname hb.workspacePath hb.focusTask
      Nothing -> pure ()

  -- Subscribe to mail: aweb.mail.> (for logging; JetStream handles persistence)
  mailSid <- Nats.subscribe env.client "aweb.mail.>" $ \_msg ->
    pure ()

  putStrLn "NATS: subscribers started (presence, mail)"
  pure $ Subscriptions [hbSid, mailSid]

-- | Stop all active subscribers.
stopSubscribers :: NatsEnv -> Subscriptions -> IO ()
stopSubscribers env (Subscriptions sids) = do
  mapM_ (Nats.unsubscribe env.client) sids
  putStrLn "NATS: subscribers stopped"

-- | Parse a heartbeat JSON payload.
parseHeartbeat :: BS.ByteString -> Maybe HeartbeatMsg
parseHeartbeat bs = case eitherDecodeStrict bs of
  Right hb -> Just hb
  Left _   -> Nothing
