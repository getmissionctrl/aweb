module Aweb.Nats.Publish
  ( publishMail
  , publishEvent
  , publishPresence
  ) where

import Data.Text (Text)
import Aweb.Nats (NatsEnv (..))

-- | Publish a mail message via NATS
publishMail :: NatsEnv -> Text -> Text -> Text -> IO ()
publishMail _env _teamId _recipientAlias _messageJson = pure ()

-- | Publish a team event via NATS
publishEvent :: NatsEnv -> Text -> Text -> IO ()
publishEvent _env _teamId _eventJson = pure ()

-- | Publish a presence heartbeat via NATS
publishPresence :: NatsEnv -> Text -> Text -> Text -> IO ()
publishPresence _env _teamId _alias _statusJson = pure ()
