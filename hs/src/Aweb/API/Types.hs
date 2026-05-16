module Aweb.API.Types
  ( -- * Common types
    TeamId
  , Alias
  , TaskRef

    -- * Agent types
  , AgentView (..)
  , RegisterAgentRequest (..)
  , ListAgentsResponse (..)
  , SuggestAliasPrefixResponse (..)

    -- * Task types
  , TaskView (..)
  , CreateTaskRequest (..)
  , UpdateTaskRequest (..)
  , ListTasksResponse (..)
  , TaskCommentView (..)
  , AddCommentRequest (..)

    -- * Workspace types
  , WorkspaceView (..)
  , RegisterWorkspaceRequest (..)
  , HeartbeatRequest (..)
  , ListWorkspacesResponse (..)

    -- * Message types
  , MessageView (..)
  , SendMessageRequest (..)
  , InboxResponse (..)

    -- * Conversation types
  , ConversationView (..)
  , CreateConversationRequest (..)

    -- * Reservation types
  , ReservationView (..)
  , AcquireReservationRequest (..)
  , RevokeReservationRequest (..)

    -- * Roles/Instructions types
  , RoleVersionView (..)
  , CreateRoleVersionRequest (..)
  , InstructionVersionView (..)
  , CreateInstructionVersionRequest (..)

    -- * Repo types
  , RepoView (..)
  , RegisterRepoRequest (..)

    -- * Claim types
  , ClaimView (..)
  , ClaimRequest (..)
  , ReleaseClaimRequest (..)

    -- * Dashboard types
  , DashboardResponse (..)

    -- * Connect types
  , ConnectResponse (..)
  ) where

import Data.Aeson (FromJSON, ToJSON, Value)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)

-- | Common type aliases
type TeamId = Text
type Alias = Text
type TaskRef = Text

-- ---------------------------------------------------------------------------
-- Agents
-- ---------------------------------------------------------------------------

data AgentView = AgentView
  { agentId       :: UUID
  , alias         :: Text
  , didKey        :: Text
  , didAw         :: Maybe Text
  , address       :: Maybe Text
  , humanName     :: Maybe Text
  , agentType     :: Maybe Text
  , workspaceType :: Maybe Text
  , role          :: Maybe Text
  , hostname      :: Maybe Text
  , workspacePath :: Maybe Text
  , status        :: Text
  , lastSeen      :: Maybe Text
  , online        :: Bool
  , lifetime      :: Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data RegisterAgentRequest = RegisterAgentRequest
  { didKey   :: Text
  , alias    :: Maybe Text
  , teamId   :: Text
  , lifetime :: Maybe Text
  , humanName :: Maybe Text
  , agentType :: Maybe Text
  , role      :: Maybe Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data ListAgentsResponse = ListAgentsResponse
  { teamId :: Text
  , agents :: [AgentView]
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data SuggestAliasPrefixResponse = SuggestAliasPrefixResponse
  { teamId     :: Text
  , namePrefix :: Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Tasks
-- ---------------------------------------------------------------------------

data TaskView = TaskView
  { taskId         :: UUID
  , taskNumber     :: Int
  , taskRefSuffix  :: Text
  , title          :: Text
  , description    :: Text
  , notes          :: Text
  , status         :: Text
  , priority       :: Int
  , taskType       :: Text
  , assigneeAlias  :: Maybe Text
  , createdByAlias :: Maybe Text
  , closedByAlias  :: Maybe Text
  , parentTaskId   :: Maybe UUID
  , createdAt      :: UTCTime
  , updatedAt      :: Maybe UTCTime
  , closedAt       :: Maybe UTCTime
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data CreateTaskRequest = CreateTaskRequest
  { title          :: Text
  , description    :: Maybe Text
  , priority       :: Maybe Int
  , taskType       :: Maybe Text
  , assigneeAlias  :: Maybe Text
  , parentTaskRef  :: Maybe Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data UpdateTaskRequest = UpdateTaskRequest
  { title          :: Maybe Text
  , description    :: Maybe Text
  , notes          :: Maybe Text
  , status         :: Maybe Text
  , priority       :: Maybe Int
  , assigneeAlias  :: Maybe Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data ListTasksResponse = ListTasksResponse
  { teamId :: Text
  , tasks  :: [TaskView]
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data TaskCommentView = TaskCommentView
  { commentId   :: UUID
  , taskId      :: UUID
  , authorAlias :: Text
  , body        :: Text
  , createdAt   :: UTCTime
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data AddCommentRequest = AddCommentRequest
  { body :: Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Workspaces
-- ---------------------------------------------------------------------------

data WorkspaceView = WorkspaceView
  { workspaceId   :: UUID
  , teamId        :: Text
  , agentId       :: UUID
  , alias         :: Text
  , humanName     :: Text
  , role          :: Maybe Text
  , hostname      :: Maybe Text
  , workspacePath :: Maybe Text
  , workspaceType :: Text
  , focusTaskRef  :: Maybe Text
  , lastSeenAt    :: Maybe UTCTime
  , createdAt     :: UTCTime
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data RegisterWorkspaceRequest = RegisterWorkspaceRequest
  { alias         :: Maybe Text
  , hostname      :: Maybe Text
  , workspacePath :: Maybe Text
  , workspaceType :: Maybe Text
  , repoUrl       :: Maybe Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data HeartbeatRequest = HeartbeatRequest
  { focusTaskRef :: Maybe Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data ListWorkspacesResponse = ListWorkspacesResponse
  { teamId     :: Text
  , workspaces :: [WorkspaceView]
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------

data MessageView = MessageView
  { messageId   :: UUID
  , fromDid     :: Text
  , toDid       :: Text
  , fromAlias   :: Text
  , toAlias     :: Text
  , subject     :: Text
  , body        :: Text
  , priority    :: Text
  , signature   :: Maybe Text
  , readAt      :: Maybe UTCTime
  , createdAt   :: UTCTime
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data SendMessageRequest = SendMessageRequest
  { toAlias    :: Maybe Text
  , toAddress  :: Maybe Text
  , subject    :: Maybe Text
  , body       :: Text
  , priority   :: Maybe Text
  , signature  :: Maybe Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data InboxResponse = InboxResponse
  { messages :: [MessageView]
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Conversations
-- ---------------------------------------------------------------------------

data ConversationView = ConversationView
  { sessionId     :: UUID
  , teamId        :: Maybe Text
  , createdBy     :: Text
  , waitSeconds   :: Maybe Int
  , createdAt     :: UTCTime
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data CreateConversationRequest = CreateConversationRequest
  { participants :: [Text]
  , waitSeconds  :: Maybe Int
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Reservations
-- ---------------------------------------------------------------------------

data ReservationView = ReservationView
  { teamId        :: Text
  , resourceKey   :: Text
  , holderAlias   :: Text
  , holderAgentId :: UUID
  , acquiredAt    :: UTCTime
  , expiresAt     :: Maybe UTCTime
  , metadataJson  :: Maybe Value
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data AcquireReservationRequest = AcquireReservationRequest
  { resourceKey  :: Text
  , expiresInSec :: Maybe Int
  , metadata     :: Maybe Value
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data RevokeReservationRequest = RevokeReservationRequest
  { resourceKey :: Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------------

data RoleVersionView = RoleVersionView
  { id             :: UUID
  , teamId         :: Text
  , version        :: Int
  , bundleJson     :: Value
  , isActive       :: Bool
  , createdByAlias :: Maybe Text
  , createdAt      :: UTCTime
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data CreateRoleVersionRequest = CreateRoleVersionRequest
  { bundleJson :: Value
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Instructions
-- ---------------------------------------------------------------------------

data InstructionVersionView = InstructionVersionView
  { id             :: UUID
  , teamId         :: Text
  , version        :: Int
  , documentJson   :: Value
  , isActive       :: Bool
  , createdByAlias :: Maybe Text
  , createdAt      :: UTCTime
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data CreateInstructionVersionRequest = CreateInstructionVersionRequest
  { documentJson :: Value
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Repos
-- ---------------------------------------------------------------------------

data RepoView = RepoView
  { repoId         :: UUID
  , teamId         :: Text
  , originUrl      :: Text
  , canonicalOrigin :: Text
  , name           :: Text
  , createdAt      :: UTCTime
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data RegisterRepoRequest = RegisterRepoRequest
  { originUrl :: Text
  , name      :: Maybe Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Claims
-- ---------------------------------------------------------------------------

data ClaimView = ClaimView
  { id          :: UUID
  , teamId      :: Text
  , workspaceId :: UUID
  , alias       :: Text
  , humanName   :: Text
  , taskRef     :: Text
  , apexTaskRef :: Maybe Text
  , claimedAt   :: UTCTime
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data ClaimRequest = ClaimRequest
  { taskRef     :: Text
  , apexTaskRef :: Maybe Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

data ReleaseClaimRequest = ReleaseClaimRequest
  { taskRef :: Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Dashboard
-- ---------------------------------------------------------------------------

data DashboardResponse = DashboardResponse
  { teamId         :: Text
  , agentCount     :: Int
  , onlineCount    :: Int
  , openTaskCount  :: Int
  , activeClaimCount :: Int
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Connect
-- ---------------------------------------------------------------------------

data ConnectResponse = ConnectResponse
  { agentId    :: UUID
  , alias      :: Text
  , teamId     :: Text
  , didKey     :: Text
  , didAw      :: Maybe Text
  , natsUrl    :: Maybe Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON, FromJSON)
