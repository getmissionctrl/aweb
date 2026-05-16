module Aweb.DB.Messages
  ( getInbox
  , insertMessage
  , markRead
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Rel8

import Aweb.DB.Schema (Message (..), messageSchema)

-- | Get unread messages for a DID (inbox).
getInbox :: Text -> Query (Message Expr)
getInbox toDid_ = do
  msg <- each messageSchema
  where_ $ msg.toDid ==. lit toDid_
  where_ $ isNull msg.readAt
  pure msg

-- | Insert a new message.
insertMessage :: Message Expr -> Insert ()
insertMessage msg = Insert
  { into = messageSchema
  , rows = values [msg]
  , onConflict = Abort
  , returning = NoReturning
  }

-- | Mark a message as read by setting readAt.
markRead :: UUID -> UTCTime -> Update ()
markRead msgId ts = Update
  { target = messageSchema
  , from = pure ()
  , set = \_ msg -> msg { readAt = lit (Just ts) }
  , updateWhere = \_ msg -> msg.messageId ==. lit msgId
  , returning = NoReturning
  }
