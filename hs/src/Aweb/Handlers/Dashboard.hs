module Aweb.Handlers.Dashboard
  ( dashboardServer
  ) where

import Control.Monad.IO.Class (liftIO)
import Rel8 qualified

import Aweb.API (DashboardAPI)
import Aweb.API.Types (DashboardResponse (..))
import Aweb.Auth.Middleware (AuthIdentity (..))
import Aweb.DB (Pool, runSelect, throwDB)
import Aweb.DB.Agents qualified as DB.Agents
import Aweb.DB.Schema (Agent (..), Task (..), TaskClaim (..), taskSchema, taskClaimSchema)
import Servant

-- | Dashboard endpoint handler with real DB calls.
dashboardServer :: Pool -> AuthIdentity -> Server DashboardAPI
dashboardServer pool identity = getDashboard
  where
    getDashboard :: Handler DashboardResponse
    getDashboard = do
      -- Look up agent to get team context
      agentResult <- liftIO $ runSelect pool (DB.Agents.getAgentByDID identity.didKey)
      agent <- case agentResult of
        Left err -> throwDB err
        Right [] -> throwError err403 { errBody = "Agent not registered" }
        Right (a:_) -> pure a

      let teamId_ = agent.teamId

      -- Count agents
      agentsResult <- liftIO $ runSelect pool (DB.Agents.listAgents teamId_)
      agentCount_ <- case agentsResult of
        Left err -> throwDB err
        Right agents -> pure (length agents)

      -- Count open tasks
      let openTasksQuery = do
            task <- Rel8.each taskSchema
            Rel8.where_ $ task.teamId Rel8.==. Rel8.lit teamId_
            Rel8.where_ $ task.status Rel8.==. Rel8.lit "open"
            Rel8.where_ $ Rel8.isNull task.deletedAt
            pure task
      tasksResult <- liftIO $ runSelect pool openTasksQuery
      openTaskCount_ <- case tasksResult of
        Left err -> throwDB err
        Right tasks -> pure (length tasks)

      -- Count active claims
      let claimsQuery = do
            claim <- Rel8.each taskClaimSchema
            Rel8.where_ $ claim.teamId Rel8.==. Rel8.lit teamId_
            pure claim
      claimsResult <- liftIO $ runSelect pool claimsQuery
      activeClaimCount_ <- case claimsResult of
        Left err -> throwDB err
        Right claims -> pure (length claims)

      pure DashboardResponse
        { teamId           = teamId_
        , agentCount       = agentCount_
        , onlineCount      = 0  -- Needs presence tracking
        , openTaskCount    = openTaskCount_
        , activeClaimCount = activeClaimCount_
        }
