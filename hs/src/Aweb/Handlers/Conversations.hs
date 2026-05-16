module Aweb.Handlers.Conversations
  ( conversationsServer
  ) where

import Control.Monad (forM_)
import Control.Monad.IO.Class (liftIO)
import Data.Int (Int32)
import Data.Time.Clock (getCurrentTime)
import Data.UUID (UUID)
import Data.UUID.V4 qualified as UUID
import Rel8 qualified

import Aweb.API (ConversationsAPI)
import Aweb.API.Types
  ( ConversationView (..)
  , CreateConversationRequest (..)
  )
import Aweb.Auth.Middleware (AuthIdentity (..))
import Aweb.DB (Pool, runSelect, runInsert, throwDB)
import Aweb.DB.Agents qualified as DB.Agents
import Aweb.DB.Schema (Agent (..), ChatParticipant (..), ChatSession (..), chatParticipantSchema, chatSessionSchema)
import Servant

-- | Conversations endpoint handlers with real DB calls.
conversationsServer :: Pool -> AuthIdentity -> Server ConversationsAPI
conversationsServer pool identity =
       createConversation
  :<|> getConversation
  where
    -- | Convert a DB ChatSession (Result) to a ConversationView.
    sessionToView :: ChatSession Rel8.Result -> ConversationView
    sessionToView session = ConversationView
      { sessionId   = session.sessionId
      , teamId      = session.teamId
      , createdBy   = session.createdBy
      , waitSeconds = fmap fromIntegral session.waitSeconds
      , createdAt   = session.createdAt
      }

    -- | Look up the authenticated agent by DID key.
    getCallerAgent :: Handler (Agent Rel8.Result)
    getCallerAgent = do
      result <- liftIO $ runSelect pool (DB.Agents.getAgentByDID identity.didKey)
      case result of
        Left err -> throwDB err
        Right []  -> throwError err403 { errBody = "Agent not registered" }
        Right (agent : _) -> pure agent

    -- | Create a new conversation (chat session) with participants.
    createConversation :: CreateConversationRequest -> Handler ConversationView
    createConversation req = do
      caller <- getCallerAgent
      newId <- liftIO UUID.nextRandom
      now <- liftIO getCurrentTime
      let sessionExpr = Rel8.lit ChatSession
            { sessionId     = newId
            , teamId        = Just caller.teamId
            , createdBy     = identity.didKey
            , waitSeconds   = fmap fromIntegral req.waitSeconds :: Maybe Int32
            , waitStartedAt = Nothing
            , waitStartedBy = Nothing
            , createdAt     = now
            }
      insertResult <- liftIO $ runInsert pool Rel8.Insert
          { into = chatSessionSchema
          , rows = Rel8.values [sessionExpr]
          , onConflict = Rel8.Abort
          , returning = Rel8.NoReturning
          }
      case insertResult of
        Left err -> throwDB err
        Right () -> pure ()
      -- Add participants
      forM_ req.participants $ \participantAlias -> do
        participantResult <- liftIO $ runSelect pool (DB.Agents.getAgentByAlias caller.teamId participantAlias)
        case participantResult of
          Left err -> throwDB err
          Right [] -> pure ()  -- Skip unknown participants
          Right (agent : _) -> do
            let participantExpr = Rel8.lit ChatParticipant
                  { sessionId = newId
                  , did       = agent.didKey
                  , agentId   = Just agent.agentId
                  , alias     = agent.alias
                  , address   = agent.address
                  , joinedAt  = now
                  }
            pResult <- liftIO $ runInsert pool Rel8.Insert
                { into = chatParticipantSchema
                , rows = Rel8.values [participantExpr]
                , onConflict = Rel8.Abort
                , returning = Rel8.NoReturning
                }
            case pResult of
              Left err -> throwDB err
              Right () -> pure ()
      -- Also add the creator as a participant
      let creatorParticipant = Rel8.lit ChatParticipant
            { sessionId = newId
            , did       = identity.didKey
            , agentId   = Just caller.agentId
            , alias     = caller.alias
            , address   = identity.address
            , joinedAt  = now
            }
      cpResult <- liftIO $ runInsert pool Rel8.Insert
          { into = chatParticipantSchema
          , rows = Rel8.values [creatorParticipant]
          , onConflict = Rel8.Abort
          , returning = Rel8.NoReturning
          }
      case cpResult of
        Left err -> throwDB err
        Right () -> pure ()
      pure ConversationView
        { sessionId   = newId
        , teamId      = Just caller.teamId
        , createdBy   = identity.didKey
        , waitSeconds = req.waitSeconds
        , createdAt   = now
        }

    -- | Get a conversation by ID, or 404 if not found.
    getConversation :: UUID -> Handler ConversationView
    getConversation convId = do
      let query = do
            session <- Rel8.each chatSessionSchema
            Rel8.where_ $ session.sessionId Rel8.==. Rel8.lit convId
            pure session
      result <- liftIO $ runSelect pool query
      case result of
        Left err -> throwDB err
        Right []  -> throwError err404 { errBody = "Conversation not found" }
        Right (session : _) -> pure (sessionToView session)
