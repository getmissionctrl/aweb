module Aweb.Handlers.Agents
  ( agentsServer
  ) where

import Control.Monad.IO.Class (liftIO)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (getCurrentTime)
import Data.UUID (UUID)
import Data.UUID.V4 qualified as UUID
import Rel8 (Result)
import Rel8 qualified

import Aweb.API (AgentsAPI)
import Aweb.API.Types
  ( AgentView (..)
  , ListAgentsResponse (..)
  , RegisterAgentRequest (..)
  , SuggestAliasPrefixResponse (..)
  )
import Aweb.Auth.Middleware (AuthIdentity (..))
import Aweb.DB (Pool, runSelect, runInsert, runUpdate, throwDB)
import Aweb.DB.Agents qualified as DB.Agents
import Aweb.DB.Schema (Agent (..))
import Servant

-- | Agents endpoint handlers with real DB calls.
agentsServer :: Pool -> AuthIdentity -> Server AgentsAPI
agentsServer pool identity =
       registerAgent
  :<|> listAgentsHandler
  :<|> getAgent
  :<|> deleteAgent
  :<|> suggestAliasPrefix
  where
    -- | Look up the authenticated agent's teamId from their DID key.
    getCallerTeamId :: Handler Text
    getCallerTeamId = do
      result <- liftIO $ runSelect pool (DB.Agents.getAgentByDID identity.didKey)
      case result of
        Left err -> throwDB err
        Right []  -> throwError err403 { errBody = "Agent not registered" }
        Right (agent : _) -> pure agent.teamId

    -- | Convert a DB Agent (Result) to an AgentView.
    agentToView :: Agent Result -> AgentView
    agentToView agent = AgentView
      { agentId       = agent.agentId
      , alias         = agent.alias
      , didKey        = agent.didKey
      , didAw         = agent.didAw
      , address       = agent.address
      , humanName     = Just agent.humanName
      , agentType     = Just agent.agentType
      , workspaceType = Nothing
      , role          = Just agent.role
      , hostname      = Nothing
      , workspacePath = Nothing
      , status        = agent.status
      , lastSeen      = Nothing
      , online        = agent.status == "active"
      , lifetime      = agent.lifetime
      }

    -- | Register a new agent.
    registerAgent :: RegisterAgentRequest -> Handler AgentView
    registerAgent req = do
      newId <- liftIO UUID.nextRandom
      now <- liftIO getCurrentTime
      let agentAlias = fromMaybe (generateAlias newId) req.alias
          agentExpr = Rel8.lit Agent
            { agentId         = newId
            , teamId          = req.teamId
            , didKey          = req.didKey
            , didAw           = Just identity.didAw
            , address         = identity.address
            , alias           = agentAlias
            , lifetime        = fromMaybe "persistent" req.lifetime
            , humanName       = fromMaybe agentAlias req.humanName
            , agentType       = fromMaybe "agent" req.agentType
            , role            = fromMaybe "worker" req.role
            , messagingPolicy = "open"
            , status          = "active"
            , createdAt       = now
            , deletedAt       = Nothing
            }
      insertResult <- liftIO $ runInsert pool (DB.Agents.insertAgent agentExpr)
      case insertResult of
        Left err -> throwDB err
        Right () -> pure AgentView
          { agentId       = newId
          , alias         = agentAlias
          , didKey        = req.didKey
          , didAw         = Just identity.didAw
          , address       = identity.address
          , humanName     = req.humanName
          , agentType     = req.agentType
          , workspaceType = Nothing
          , role          = req.role
          , hostname      = Nothing
          , workspacePath = Nothing
          , status        = "active"
          , lastSeen      = Nothing
          , online        = True
          , lifetime      = fromMaybe "persistent" req.lifetime
          }

    -- | List all agents for the caller's team.
    listAgentsHandler :: Handler ListAgentsResponse
    listAgentsHandler = do
      teamId_ <- getCallerTeamId
      result <- liftIO $ runSelect pool (DB.Agents.listAgents teamId_)
      case result of
        Left err -> throwDB err
        Right agents -> pure ListAgentsResponse
          { teamId = teamId_
          , agents = map agentToView agents
          }

    -- | Get a specific agent by alias within the caller's team.
    getAgent :: Text -> Handler AgentView
    getAgent alias_ = do
      teamId_ <- getCallerTeamId
      result <- liftIO $ runSelect pool (DB.Agents.getAgentByAlias teamId_ alias_)
      case result of
        Left err -> throwDB err
        Right []  -> throwError err404 { errBody = "Agent not found" }
        Right (agent : _) -> pure (agentToView agent)

    -- | Soft-delete an agent by alias.
    deleteAgent :: Text -> Handler NoContent
    deleteAgent alias_ = do
      teamId_ <- getCallerTeamId
      -- First find the agent to get its ID
      lookupResult <- liftIO $ runSelect pool (DB.Agents.getAgentByAlias teamId_ alias_)
      case lookupResult of
        Left err -> throwDB err
        Right []  -> throwError err404 { errBody = "Agent not found" }
        Right (agent : _) -> do
          now <- liftIO getCurrentTime
          delResult <- liftIO $ runUpdate pool (DB.Agents.softDeleteAgent agent.agentId now)
          case delResult of
            Left err -> throwDB err
            Right () -> pure NoContent

    -- | Suggest an alias prefix for new agents in the team.
    suggestAliasPrefix :: Handler SuggestAliasPrefixResponse
    suggestAliasPrefix = do
      teamId_ <- getCallerTeamId
      result <- liftIO $ runSelect pool (DB.Agents.listAgents teamId_)
      case result of
        Left err -> throwDB err
        Right agents -> pure SuggestAliasPrefixResponse
          { teamId     = teamId_
          , namePrefix = "agent-" <> T.pack (show (length agents + 1))
          }

-- | Generate a simple alias from a UUID (first 8 hex chars).
generateAlias :: UUID -> Text
generateAlias uuid_ = "agent-" <> T.take 8 (T.filter (/= '-') (T.pack (show uuid_)))
