module Aweb.Handlers.Claims
  ( claimsServer
  ) where

import Control.Monad.IO.Class (liftIO)
import Data.Text (Text)
import Data.Time.Clock (getCurrentTime)
import Data.UUID.V4 qualified as UUID
import Rel8 qualified

import Aweb.API (ClaimsAPI)
import Aweb.API.Types
  ( ClaimRequest (..)
  , ClaimView (..)
  , ReleaseClaimRequest (..)
  )
import Aweb.Auth.Middleware (AuthIdentity (..))
import Aweb.DB (Pool, runSelect, runInsert, runDelete, throwDB)
import Aweb.DB.Agents qualified as DB.Agents
import Aweb.DB.Schema (Agent (..), TaskClaim (..), Workspace (..), taskClaimSchema, workspaceSchema)
import Servant

-- | Claims endpoint handlers with real DB calls.
claimsServer :: Pool -> AuthIdentity -> Server ClaimsAPI
claimsServer pool identity =
       claimTask
  :<|> listClaimsHandler
  :<|> releaseClaim
  where
    -- | Look up the authenticated agent by DID key.
    lookupAgent :: Handler (Agent Rel8.Result)
    lookupAgent = do
      result <- liftIO $ runSelect pool (DB.Agents.getAgentByDID identity.didKey)
      case result of
        Left err -> throwDB err
        Right [] -> throwError err403 { errBody = "Agent not registered" }
        Right (a:_) -> pure a

    -- | Find the active workspace for a given agent.
    getAgentWorkspace :: Agent Rel8.Result -> Handler (Workspace Rel8.Result)
    getAgentWorkspace agent = do
      let query = do
            ws <- Rel8.each workspaceSchema
            Rel8.where_ $ ws.agentId Rel8.==. Rel8.lit agent.agentId
            Rel8.where_ $ Rel8.isNull ws.deletedAt
            pure ws
      result <- liftIO $ runSelect pool query
      case result of
        Left err -> throwDB err
        Right [] -> throwError err404 { errBody = "No active workspace for agent" }
        Right (ws:_) -> pure ws

    -- | Convert a DB TaskClaim to a ClaimView.
    claimToView :: TaskClaim Rel8.Result -> ClaimView
    claimToView claim = ClaimView
      { id          = claim.taskClaimId
      , teamId      = claim.teamId
      , workspaceId = claim.workspaceId
      , alias       = claim.alias
      , humanName   = claim.humanName
      , taskRef     = claim.taskRef
      , apexTaskRef = claim.apexTaskRef
      , claimedAt   = claim.claimedAt
      }

    -- | List claims for the team.
    listClaimsQuery :: Text -> Rel8.Query (TaskClaim Rel8.Expr)
    listClaimsQuery teamId_ = do
      claim <- Rel8.each taskClaimSchema
      Rel8.where_ $ claim.teamId Rel8.==. Rel8.lit teamId_
      pure claim

    -- | Claim a task.
    claimTask :: ClaimRequest -> Handler ClaimView
    claimTask req = do
      agent <- lookupAgent
      ws <- getAgentWorkspace agent
      newId <- liftIO UUID.nextRandom
      now <- liftIO getCurrentTime
      let claimExpr = Rel8.lit TaskClaim
            { taskClaimId = newId
            , teamId      = agent.teamId
            , workspaceId = ws.workspaceId
            , alias       = agent.alias
            , humanName   = agent.humanName
            , taskRef     = req.taskRef
            , apexTaskRef = req.apexTaskRef
            , claimedAt   = now
            }
          insertClaim = Rel8.Insert
            { into = taskClaimSchema
            , rows = Rel8.values [claimExpr]
            , onConflict = Rel8.Abort
            , returning = Rel8.NoReturning
            }
      insertResult <- liftIO $ runInsert pool insertClaim
      case insertResult of
        Left err -> throwDB err
        Right () -> pure ClaimView
          { id          = newId
          , teamId      = agent.teamId
          , workspaceId = ws.workspaceId
          , alias       = agent.alias
          , humanName   = agent.humanName
          , taskRef     = req.taskRef
          , apexTaskRef = req.apexTaskRef
          , claimedAt   = now
          }

    -- | List all claims for the team.
    listClaimsHandler :: Handler [ClaimView]
    listClaimsHandler = do
      agent <- lookupAgent
      result <- liftIO $ runSelect pool (listClaimsQuery agent.teamId)
      case result of
        Left err -> throwDB err
        Right claims -> pure (map claimToView claims)

    -- | Release a claim by task ref.
    releaseClaim :: ReleaseClaimRequest -> Handler NoContent
    releaseClaim req = do
      agent <- lookupAgent
      let deleteClaim = Rel8.Delete
            { from = taskClaimSchema
            , using = pure ()
            , deleteWhere = \_ claim ->
                claim.teamId Rel8.==. Rel8.lit agent.teamId
                Rel8.&&. claim.taskRef Rel8.==. Rel8.lit req.taskRef
            , returning = Rel8.NoReturning
            }
      delResult <- liftIO $ runDelete pool deleteClaim
      case delResult of
        Left err -> throwDB err
        Right () -> pure NoContent
