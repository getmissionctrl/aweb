{-# OPTIONS_GHC -Wno-orphans #-}
module Aweb.API
  ( API
  , HealthStatus (..)
  , ProtectedAPI
  , AgentsAPI
  , TasksAPI
  , WorkspacesAPI
  , MessagesAPI
  , ConversationsAPI
  , ReservationsAPI
  , RolesAPI
  , InstructionsAPI
  , ReposAPI
  , ClaimsAPI
  , DashboardAPI
  , ConnectAPI
  ) where

import Data.Aeson (ToJSON, Value)
import Data.Text (Text)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import Servant
import Servant.Server.Experimental.Auth (AuthServerData)

import Aweb.API.Types
import Aweb.Auth.Middleware (AuthIdentity)

-- | Wire AuthProtect to produce AuthIdentity
type instance AuthServerData (AuthProtect "did") = AuthIdentity

-- ---------------------------------------------------------------------------
-- Health
-- ---------------------------------------------------------------------------

data HealthStatus = HealthStatus
  { status  :: Text
  , version :: Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON)

-- ---------------------------------------------------------------------------
-- Top-level API
-- ---------------------------------------------------------------------------

type API =
       "health" :> Get '[JSON] HealthStatus
  :<|> AuthProtect "did" :> ProtectedAPI

type ProtectedAPI =
       "v1" :> "agents" :> AgentsAPI
  :<|> "v1" :> "tasks" :> TasksAPI
  :<|> "v1" :> "workspaces" :> WorkspacesAPI
  :<|> "v1" :> "messages" :> MessagesAPI
  :<|> "v1" :> "conversations" :> ConversationsAPI
  :<|> "v1" :> "reservations" :> ReservationsAPI
  :<|> "v1" :> "roles" :> RolesAPI
  :<|> "v1" :> "instructions" :> InstructionsAPI
  :<|> "v1" :> "repos" :> ReposAPI
  :<|> "v1" :> "claims" :> ClaimsAPI
  :<|> "v1" :> "dashboard" :> DashboardAPI
  :<|> "v1" :> "connect" :> ConnectAPI

-- ---------------------------------------------------------------------------
-- Agents API
-- ---------------------------------------------------------------------------

type AgentsAPI =
       ReqBody '[JSON] RegisterAgentRequest :> Post '[JSON] AgentView
  :<|> Get '[JSON] ListAgentsResponse
  :<|> Capture "alias" Alias :> Get '[JSON] AgentView
  :<|> Capture "alias" Alias :> Delete '[JSON] NoContent
  :<|> "suggest-alias-prefix" :> Get '[JSON] SuggestAliasPrefixResponse

-- ---------------------------------------------------------------------------
-- Tasks API
-- ---------------------------------------------------------------------------

type TasksAPI =
       ReqBody '[JSON] CreateTaskRequest :> Post '[JSON] TaskView
  :<|> QueryParam "status" Text :> QueryParam "assignee" Text :> Get '[JSON] ListTasksResponse
  :<|> Capture "ref" TaskRef :> Get '[JSON] TaskView
  :<|> Capture "ref" TaskRef :> ReqBody '[JSON] UpdateTaskRequest :> Patch '[JSON] TaskView
  :<|> Capture "ref" TaskRef :> Delete '[JSON] NoContent
  :<|> Capture "ref" TaskRef :> "comments" :> ReqBody '[JSON] AddCommentRequest :> Post '[JSON] TaskCommentView
  :<|> Capture "ref" TaskRef :> "comments" :> Get '[JSON] [TaskCommentView]
  :<|> Capture "ref" TaskRef :> "deps" :> ReqBody '[JSON] Value :> Post '[JSON] NoContent
  :<|> Capture "ref" TaskRef :> "deps" :> Capture "dep_ref" TaskRef :> Delete '[JSON] NoContent

-- ---------------------------------------------------------------------------
-- Workspaces API
-- ---------------------------------------------------------------------------

type WorkspacesAPI =
       ReqBody '[JSON] RegisterWorkspaceRequest :> Post '[JSON] WorkspaceView
  :<|> "heartbeat" :> ReqBody '[JSON] HeartbeatRequest :> Post '[JSON] WorkspaceView
  :<|> Get '[JSON] ListWorkspacesResponse
  :<|> Capture "workspace_id" UUID :> Get '[JSON] WorkspaceView
  :<|> "deactivate" :> Post '[JSON] NoContent
  :<|> Capture "workspace_id" UUID :> Delete '[JSON] NoContent

-- ---------------------------------------------------------------------------
-- Messages API
-- ---------------------------------------------------------------------------

type MessagesAPI =
       ReqBody '[JSON] SendMessageRequest :> Post '[JSON] MessageView
  :<|> "inbox" :> Get '[JSON] InboxResponse
  :<|> Capture "message_id" UUID :> "ack" :> Post '[JSON] NoContent

-- ---------------------------------------------------------------------------
-- Conversations API
-- ---------------------------------------------------------------------------

type ConversationsAPI =
       ReqBody '[JSON] CreateConversationRequest :> Post '[JSON] ConversationView
  :<|> Capture "conversation_id" UUID :> Get '[JSON] ConversationView

-- ---------------------------------------------------------------------------
-- Reservations API
-- ---------------------------------------------------------------------------

type ReservationsAPI =
       ReqBody '[JSON] AcquireReservationRequest :> Post '[JSON] ReservationView
  :<|> Get '[JSON] [ReservationView]
  :<|> "revoke" :> ReqBody '[JSON] RevokeReservationRequest :> Post '[JSON] NoContent

-- ---------------------------------------------------------------------------
-- Roles API
-- ---------------------------------------------------------------------------

type RolesAPI =
       ReqBody '[JSON] CreateRoleVersionRequest :> Post '[JSON] RoleVersionView
  :<|> Get '[JSON] [RoleVersionView]
  :<|> "active" :> Get '[JSON] RoleVersionView
  :<|> Capture "version" Int :> "activate" :> Post '[JSON] RoleVersionView

-- ---------------------------------------------------------------------------
-- Instructions API
-- ---------------------------------------------------------------------------

type InstructionsAPI =
       ReqBody '[JSON] CreateInstructionVersionRequest :> Post '[JSON] InstructionVersionView
  :<|> Get '[JSON] [InstructionVersionView]
  :<|> "active" :> Get '[JSON] InstructionVersionView
  :<|> Capture "version" Int :> "activate" :> Post '[JSON] InstructionVersionView

-- ---------------------------------------------------------------------------
-- Repos API
-- ---------------------------------------------------------------------------

type ReposAPI =
       ReqBody '[JSON] RegisterRepoRequest :> Post '[JSON] RepoView
  :<|> Get '[JSON] [RepoView]
  :<|> Capture "repo_id" UUID :> Get '[JSON] RepoView

-- ---------------------------------------------------------------------------
-- Claims API
-- ---------------------------------------------------------------------------

type ClaimsAPI =
       ReqBody '[JSON] ClaimRequest :> Post '[JSON] ClaimView
  :<|> Get '[JSON] [ClaimView]
  :<|> "release" :> ReqBody '[JSON] ReleaseClaimRequest :> Post '[JSON] NoContent

-- ---------------------------------------------------------------------------
-- Dashboard API
-- ---------------------------------------------------------------------------

type DashboardAPI = Get '[JSON] DashboardResponse

-- ---------------------------------------------------------------------------
-- Connect API
-- ---------------------------------------------------------------------------

type ConnectAPI = Get '[JSON] ConnectResponse
