module Aweb.Handlers.Messages
  ( messagesServer
  ) where

import Control.Monad.IO.Class (liftIO)
import Data.Maybe (fromMaybe)
import Data.Time.Clock (getCurrentTime)
import Data.UUID (UUID)
import Data.UUID.V4 qualified as UUID
import Rel8 qualified

import Aweb.API (MessagesAPI)
import Aweb.API.Types
  ( InboxResponse (..)
  , MessageView (..)
  , SendMessageRequest (..)
  )
import Aweb.Auth.Middleware (AuthIdentity (..))
import Aweb.DB (Pool, runSelect, runInsert, runUpdate, throwDB)
import Aweb.DB.Agents qualified as DB.Agents
import Aweb.DB.Messages qualified as DB.Messages
import Aweb.DB.Schema (Agent (..), Message (..))
import Servant

-- | Messages endpoint handlers with real DB calls.
messagesServer :: Pool -> AuthIdentity -> Server MessagesAPI
messagesServer pool identity =
       sendMessage
  :<|> getInboxHandler
  :<|> ackMessage
  where
    -- | Look up the authenticated agent by DID key.
    getCallerAgent :: Handler (Agent Rel8.Result)
    getCallerAgent = do
      result <- liftIO $ runSelect pool (DB.Agents.getAgentByDID identity.didKey)
      case result of
        Left err -> throwDB err
        Right []  -> throwError err403 { errBody = "Agent not registered" }
        Right (agent : _) -> pure agent

    -- | Convert a DB Message (Result) to a MessageView.
    messageToView :: Message Rel8.Result -> MessageView
    messageToView msg = MessageView
      { messageId = msg.messageId
      , fromDid   = msg.fromDid
      , toDid     = msg.toDid
      , fromAlias = msg.fromAlias
      , toAlias   = msg.toAlias
      , subject   = msg.subject
      , body      = msg.body
      , priority  = msg.priority
      , signature = msg.signature
      , readAt    = msg.readAt
      , createdAt = msg.createdAt
      }

    -- | Send a message to a recipient resolved by alias.
    sendMessage :: SendMessageRequest -> Handler MessageView
    sendMessage req = do
      sender <- getCallerAgent
      let recipientAlias = fromMaybe "" req.toAlias
      -- Resolve recipient by alias within sender's team
      recipientResult <- liftIO $ runSelect pool (DB.Agents.getAgentByAlias sender.teamId recipientAlias)
      recipient <- case recipientResult of
        Left err -> throwDB err
        Right []  -> throwError err404 { errBody = "Recipient not found" }
        Right (agent : _) -> pure agent
      -- Generate new message ID and timestamp
      newId <- liftIO UUID.nextRandom
      now <- liftIO getCurrentTime
      let recipientDid = fromMaybe recipient.didKey recipient.didAw
          msgExpr = Rel8.lit Message
            { messageId     = newId
            , fromDid       = identity.didKey
            , toDid         = recipientDid
            , fromAlias     = sender.alias
            , fromAddress   = identity.address
            , toAlias       = recipientAlias
            , subject       = fromMaybe "" req.subject
            , body          = req.body
            , priority      = fromMaybe "normal" req.priority
            , teamId        = Just sender.teamId
            , fromAgentId   = Just sender.agentId
            , toAgentId     = Just recipient.agentId
            , signature     = req.signature
            , signedPayload = Nothing
            , readAt        = Nothing
            , createdAt     = now
            }
      insertResult <- liftIO $ runInsert pool (DB.Messages.insertMessage msgExpr)
      case insertResult of
        Left err -> throwDB err
        Right () -> pure MessageView
          { messageId = newId
          , fromDid   = identity.didKey
          , toDid     = recipientDid
          , fromAlias = sender.alias
          , toAlias   = recipientAlias
          , subject   = fromMaybe "" req.subject
          , body      = req.body
          , priority  = fromMaybe "normal" req.priority
          , signature = req.signature
          , readAt    = Nothing
          , createdAt = now
          }

    -- | Get inbox (unread messages) for the authenticated identity.
    getInboxHandler :: Handler InboxResponse
    getInboxHandler = do
      let lookupDid = identity.didAw
      result <- liftIO $ runSelect pool (DB.Messages.getInbox lookupDid)
      case result of
        Left err -> throwDB err
        Right msgs -> pure InboxResponse { messages = map messageToView msgs }

    -- | Acknowledge (mark as read) a message by ID.
    ackMessage :: UUID -> Handler NoContent
    ackMessage msgId = do
      now <- liftIO getCurrentTime
      result <- liftIO $ runUpdate pool (DB.Messages.markRead msgId now)
      case result of
        Left err -> throwDB err
        Right () -> pure NoContent
