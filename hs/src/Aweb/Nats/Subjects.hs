module Aweb.Nats.Subjects
  ( mailSubject
  , chatSubject
  , presenceSubject
  , eventsSubject
  ) where

import Data.Text (Text)
import Data.Text qualified as T

-- | Subject for async mail delivery: aweb.mail.<team>.<alias>
mailSubject :: Text -> Text -> Text
mailSubject teamId alias = T.intercalate "." ["aweb", "mail", teamId, alias]

-- | Subject for chat request-reply: agents.prompt.aweb.<team>.<alias>
chatSubject :: Text -> Text -> Text
chatSubject teamId alias = T.intercalate "." ["agents", "prompt", "aweb", teamId, alias]

-- | Subject for presence heartbeat: agents.hb.aweb.<team>.<alias>
presenceSubject :: Text -> Text -> Text
presenceSubject teamId alias = T.intercalate "." ["agents", "hb", "aweb", teamId, alias]

-- | Subject for team events: aweb.events.<team>
eventsSubject :: Text -> Text
eventsSubject teamId = T.intercalate "." ["aweb", "events", teamId]
