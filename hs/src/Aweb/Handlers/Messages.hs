module Aweb.Handlers.Messages
  ( messagesServer
  ) where

import Aweb.API (MessagesAPI)
import Servant

-- | Messages endpoint handlers (stub implementation)
messagesServer :: Server MessagesAPI
messagesServer =
       sendMessage
  :<|> getInbox
  :<|> ackMessage
  where
    sendMessage _req = throwError err501
    getInbox = throwError err501
    ackMessage _msgId = throwError err501
