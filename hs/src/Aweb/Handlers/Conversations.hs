module Aweb.Handlers.Conversations
  ( conversationsServer
  ) where

import Aweb.API (ConversationsAPI)
import Servant

-- | Conversations endpoint handlers (stub implementation)
conversationsServer :: Server ConversationsAPI
conversationsServer =
       createConversation
  :<|> getConversation
  where
    createConversation _req = throwError err501
    getConversation _convId = throwError err501
