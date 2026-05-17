module Aweb.Nats.Publish
  ( publishMail
  , publishEvent
  , publishPresence
  ) where

import Aweb.Nats (NatsEnv (..))
import Aweb.Nats.Subjects (mailSubject, eventsSubject, presenceSubject)
import Client qualified as Nats
import Data.Text (Text)
import Data.Text.Encoding qualified as TE

-- | Publish a mail message to the recipient's mail subject via NATS.
publishMail :: NatsEnv -> Text -> Text -> Text -> IO ()
publishMail env teamId recipientAlias messageJson =
  Nats.publish env.client (TE.encodeUtf8 (mailSubject teamId recipientAlias))
    [Nats.withPayload (TE.encodeUtf8 messageJson)]

-- | Publish a team event via NATS.
publishEvent :: NatsEnv -> Text -> Text -> IO ()
publishEvent env teamId eventJson =
  Nats.publish env.client (TE.encodeUtf8 (eventsSubject teamId))
    [Nats.withPayload (TE.encodeUtf8 eventJson)]

-- | Publish a presence heartbeat via NATS.
publishPresence :: NatsEnv -> Text -> Text -> Text -> IO ()
publishPresence env teamId alias statusJson =
  Nats.publish env.client (TE.encodeUtf8 (presenceSubject teamId alias))
    [Nats.withPayload (TE.encodeUtf8 statusJson)]
