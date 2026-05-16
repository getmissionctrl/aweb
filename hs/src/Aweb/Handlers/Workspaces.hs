module Aweb.Handlers.Workspaces
  ( workspacesServer
  ) where

import Control.Monad.IO.Class (liftIO)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Time.Clock (getCurrentTime)
import Data.UUID (UUID)
import Data.UUID.V4 qualified as UUID
import Rel8 qualified

import Aweb.API (WorkspacesAPI)
import Aweb.API.Types
  ( HeartbeatRequest (..)
  , ListWorkspacesResponse (..)
  , RegisterWorkspaceRequest (..)
  , WorkspaceView (..)
  )
import Aweb.Auth.Middleware (AuthIdentity (..))
import Aweb.DB (Pool, runSelect, runInsert, runUpdate, throwDB)
import Aweb.DB.Agents qualified as DB.Agents
import Aweb.DB.Schema (Agent (..), Workspace (..), workspaceSchema)
import Aweb.DB.Workspaces qualified as DB.Workspaces
import Servant

-- | Workspaces endpoint handlers with real DB calls.
workspacesServer :: Pool -> AuthIdentity -> Server WorkspacesAPI
workspacesServer pool identity =
       registerWorkspace
  :<|> heartbeat
  :<|> listWorkspacesHandler
  :<|> getWorkspaceHandler
  :<|> deactivate
  :<|> deleteWorkspace
  where
    -- | Look up the authenticated agent by DID key, returning teamId and agent.
    getCallerAgent :: Handler (Text, Agent Rel8.Result)
    getCallerAgent = do
      result <- liftIO $ runSelect pool (DB.Agents.getAgentByDID identity.didKey)
      case result of
        Left err -> throwDB err
        Right [] -> throwError err403 { errBody = "Agent not found" }
        Right (agent : _) -> pure (agent.teamId, agent)

    -- | Find the active (non-deleted) workspace for a given agent.
    getAgentWorkspace :: UUID -> Handler (Workspace Rel8.Result)
    getAgentWorkspace agentId_ = do
      let query = do
            ws <- Rel8.each workspaceSchema
            Rel8.where_ $ ws.agentId Rel8.==. Rel8.lit agentId_
            Rel8.where_ $ Rel8.isNull ws.deletedAt
            pure ws
      result <- liftIO $ runSelect pool query
      case result of
        Left err -> throwDB err
        Right [] -> throwError err404 { errBody = "No active workspace for agent" }
        Right (ws : _) -> pure ws

    -- | Convert a DB Workspace (Result) to a WorkspaceView.
    workspaceToView :: Workspace Rel8.Result -> WorkspaceView
    workspaceToView ws = WorkspaceView
      { workspaceId   = ws.workspaceId
      , teamId        = ws.teamId
      , agentId       = ws.agentId
      , alias         = ws.alias
      , humanName     = ws.humanName
      , role          = ws.role
      , hostname      = ws.hostname
      , workspacePath = ws.workspacePath
      , workspaceType = ws.workspaceType
      , focusTaskRef  = ws.focusTaskRef
      , lastSeenAt    = ws.lastSeenAt
      , createdAt     = ws.createdAt
      }

    -- | Register a new workspace for the authenticated agent.
    registerWorkspace :: RegisterWorkspaceRequest -> Handler WorkspaceView
    registerWorkspace req = do
      (teamId_, agent) <- getCallerAgent
      newId <- liftIO UUID.nextRandom
      now <- liftIO getCurrentTime
      let wsAlias = fromMaybe agent.alias req.alias
          wsType = fromMaybe "development" req.workspaceType
          wsExpr = Rel8.lit Workspace
            { workspaceId    = newId
            , teamId         = teamId_
            , agentId        = agent.agentId
            , repoId         = Nothing
            , alias          = wsAlias
            , humanName      = agent.humanName
            , role           = Just agent.role
            , hostname       = req.hostname
            , workspacePath  = req.workspacePath
            , workspaceType  = wsType
            , focusTaskRef   = Nothing
            , focusUpdatedAt = Nothing
            , lastSeenAt     = Just now
            , createdAt      = now
            , updatedAt      = Nothing
            , deletedAt      = Nothing
            }
      insertResult <- liftIO $ runInsert pool (DB.Workspaces.insertWorkspace wsExpr)
      case insertResult of
        Left err -> throwDB err
        Right () -> pure WorkspaceView
          { workspaceId   = newId
          , teamId        = teamId_
          , agentId       = agent.agentId
          , alias         = wsAlias
          , humanName     = agent.humanName
          , role          = Just agent.role
          , hostname      = req.hostname
          , workspacePath = req.workspacePath
          , workspaceType = wsType
          , focusTaskRef  = Nothing
          , lastSeenAt    = Just now
          , createdAt     = now
          }

    -- | Heartbeat: update lastSeenAt and optionally focusTaskRef.
    heartbeat :: HeartbeatRequest -> Handler WorkspaceView
    heartbeat req = do
      (_, agent) <- getCallerAgent
      ws <- getAgentWorkspace agent.agentId
      now <- liftIO getCurrentTime
      let heartbeatUpdate = Rel8.Update
            { target = workspaceSchema
            , from = pure ()
            , set = \_ row -> row
                { lastSeenAt    = Rel8.lit (Just now)
                , focusTaskRef  = Rel8.lit req.focusTaskRef
                , focusUpdatedAt = case req.focusTaskRef of
                    Just _  -> Rel8.lit (Just now)
                    Nothing -> row.focusUpdatedAt
                , updatedAt = Rel8.lit (Just now)
                }
            , updateWhere = \_ row -> row.workspaceId Rel8.==. Rel8.lit ws.workspaceId
            , returning = Rel8.NoReturning
            }
      updateResult <- liftIO $ runUpdate pool heartbeatUpdate
      case updateResult of
        Left err -> throwDB err
        Right () -> pure WorkspaceView
          { workspaceId   = ws.workspaceId
          , teamId        = ws.teamId
          , agentId       = ws.agentId
          , alias         = ws.alias
          , humanName     = ws.humanName
          , role          = ws.role
          , hostname      = ws.hostname
          , workspacePath = ws.workspacePath
          , workspaceType = ws.workspaceType
          , focusTaskRef  = req.focusTaskRef
          , lastSeenAt    = Just now
          , createdAt     = ws.createdAt
          }

    -- | List all workspaces for the authenticated agent's team.
    listWorkspacesHandler :: Handler ListWorkspacesResponse
    listWorkspacesHandler = do
      (teamId_, _) <- getCallerAgent
      result <- liftIO $ runSelect pool (DB.Workspaces.listWorkspaces teamId_)
      case result of
        Left err -> throwDB err
        Right wss -> pure ListWorkspacesResponse
          { teamId     = teamId_
          , workspaces = map workspaceToView wss
          }

    -- | Get a specific workspace by ID.
    getWorkspaceHandler :: UUID -> Handler WorkspaceView
    getWorkspaceHandler wsId = do
      result <- liftIO $ runSelect pool (DB.Workspaces.getWorkspace wsId)
      case result of
        Left err -> throwDB err
        Right [] -> throwError err404 { errBody = "Workspace not found" }
        Right (ws : _) -> pure (workspaceToView ws)

    -- | Deactivate the authenticated agent's workspace (soft-delete).
    deactivate :: Handler NoContent
    deactivate = do
      (_, agent) <- getCallerAgent
      ws <- getAgentWorkspace agent.agentId
      now <- liftIO getCurrentTime
      delResult <- liftIO $ runUpdate pool (DB.Workspaces.softDeleteWorkspace ws.workspaceId now)
      case delResult of
        Left err -> throwDB err
        Right () -> pure NoContent

    -- | Delete (soft-delete) a workspace by ID.
    deleteWorkspace :: UUID -> Handler NoContent
    deleteWorkspace wsId = do
      now <- liftIO getCurrentTime
      delResult <- liftIO $ runUpdate pool (DB.Workspaces.softDeleteWorkspace wsId now)
      case delResult of
        Left err -> throwDB err
        Right () -> pure NoContent
