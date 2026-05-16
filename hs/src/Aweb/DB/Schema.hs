module Aweb.DB.Schema
  ( -- * Teams
    Team (..)
  , teamSchema
    -- * Agents
  , Agent (..)
  , agentSchema
    -- * Messages
  , Message (..)
  , messageSchema
    -- * Workspaces
  , Workspace (..)
  , workspaceSchema
    -- * Tasks
  , Task (..)
  , taskSchema
    -- * Task Comments
  , TaskComment (..)
  , taskCommentSchema
    -- * Task Dependencies
  , TaskDependency (..)
  , taskDependencySchema
    -- * Reservations
  , Reservation (..)
  , reservationSchema
    -- * Team Roles
  , TeamRole (..)
  , teamRoleSchema
    -- * Team Instructions
  , TeamInstruction (..)
  , teamInstructionSchema
    -- * Repos
  , Repo (..)
  , repoSchema
    -- * Task Claims
  , TaskClaim (..)
  , taskClaimSchema
    -- * Chat Sessions
  , ChatSession (..)
  , chatSessionSchema
    -- * Chat Participants
  , ChatParticipant (..)
  , chatParticipantSchema
    -- * Chat Messages
  , ChatMessage (..)
  , chatMessageSchema
  ) where

import Data.Int (Int32)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import Rel8

------------------------------------------------------------------------
-- Teams
------------------------------------------------------------------------

data Team f = Team
  { teamId    :: Column f Text
  , namespace :: Column f Text
  , teamName  :: Column f Text
  , teamDidKey :: Column f Text
  , createdAt :: Column f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (Team f)

teamSchema :: TableSchema (Team Name)
teamSchema = TableSchema
  { name = "teams"
  , columns = Team
      { teamId    = "team_id"
      , namespace = "namespace"
      , teamName  = "team_name"
      , teamDidKey = "team_did_key"
      , createdAt = "created_at"
      }
  }

------------------------------------------------------------------------
-- Agents
------------------------------------------------------------------------

data Agent f = Agent
  { agentId         :: Column f UUID
  , teamId          :: Column f Text
  , didKey          :: Column f Text
  , didAw           :: Column f (Maybe Text)
  , address         :: Column f (Maybe Text)
  , alias           :: Column f Text
  , lifetime        :: Column f Text
  , humanName       :: Column f Text
  , agentType       :: Column f Text
  , role            :: Column f Text
  , messagingPolicy :: Column f Text
  , status          :: Column f Text
  , createdAt       :: Column f UTCTime
  , deletedAt       :: Column f (Maybe UTCTime)
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (Agent f)

agentSchema :: TableSchema (Agent Name)
agentSchema = TableSchema
  { name = "agents"
  , columns = Agent
      { agentId         = "agent_id"
      , teamId          = "team_id"
      , didKey          = "did_key"
      , didAw           = "did_aw"
      , address         = "address"
      , alias           = "alias"
      , lifetime        = "lifetime"
      , humanName       = "human_name"
      , agentType       = "agent_type"
      , role            = "role"
      , messagingPolicy = "messaging_policy"
      , status          = "status"
      , createdAt       = "created_at"
      , deletedAt       = "deleted_at"
      }
  }

------------------------------------------------------------------------
-- Messages
------------------------------------------------------------------------

data Message f = Message
  { messageId     :: Column f UUID
  , fromDid       :: Column f Text
  , toDid         :: Column f Text
  , fromAlias     :: Column f Text
  , fromAddress   :: Column f (Maybe Text)
  , toAlias       :: Column f Text
  , subject       :: Column f Text
  , body          :: Column f Text
  , priority      :: Column f Text
  , teamId        :: Column f (Maybe Text)
  , fromAgentId   :: Column f (Maybe UUID)
  , toAgentId     :: Column f (Maybe UUID)
  , signature     :: Column f (Maybe Text)
  , signedPayload :: Column f (Maybe Text)
  , readAt        :: Column f (Maybe UTCTime)
  , createdAt     :: Column f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (Message f)

messageSchema :: TableSchema (Message Name)
messageSchema = TableSchema
  { name = "messages"
  , columns = Message
      { messageId     = "message_id"
      , fromDid       = "from_did"
      , toDid         = "to_did"
      , fromAlias     = "from_alias"
      , fromAddress   = "from_address"
      , toAlias       = "to_alias"
      , subject       = "subject"
      , body          = "body"
      , priority      = "priority"
      , teamId        = "team_id"
      , fromAgentId   = "from_agent_id"
      , toAgentId     = "to_agent_id"
      , signature     = "signature"
      , signedPayload = "signed_payload"
      , readAt        = "read_at"
      , createdAt     = "created_at"
      }
  }

------------------------------------------------------------------------
-- Workspaces
------------------------------------------------------------------------

data Workspace f = Workspace
  { workspaceId    :: Column f UUID
  , teamId         :: Column f Text
  , agentId        :: Column f UUID
  , repoId         :: Column f (Maybe UUID)
  , alias          :: Column f Text
  , humanName      :: Column f Text
  , role           :: Column f (Maybe Text)
  , hostname       :: Column f (Maybe Text)
  , workspacePath  :: Column f (Maybe Text)
  , workspaceType  :: Column f Text
  , focusTaskRef   :: Column f (Maybe Text)
  , focusUpdatedAt :: Column f (Maybe UTCTime)
  , lastSeenAt     :: Column f (Maybe UTCTime)
  , createdAt      :: Column f UTCTime
  , updatedAt      :: Column f (Maybe UTCTime)
  , deletedAt      :: Column f (Maybe UTCTime)
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (Workspace f)

workspaceSchema :: TableSchema (Workspace Name)
workspaceSchema = TableSchema
  { name = "workspaces"
  , columns = Workspace
      { workspaceId    = "workspace_id"
      , teamId         = "team_id"
      , agentId        = "agent_id"
      , repoId         = "repo_id"
      , alias          = "alias"
      , humanName      = "human_name"
      , role           = "role"
      , hostname       = "hostname"
      , workspacePath  = "workspace_path"
      , workspaceType  = "workspace_type"
      , focusTaskRef   = "focus_task_ref"
      , focusUpdatedAt = "focus_updated_at"
      , lastSeenAt     = "last_seen_at"
      , createdAt      = "created_at"
      , updatedAt      = "updated_at"
      , deletedAt      = "deleted_at"
      }
  }

------------------------------------------------------------------------
-- Tasks
------------------------------------------------------------------------

data Task f = Task
  { taskId         :: Column f UUID
  , teamId         :: Column f Text
  , taskNumber     :: Column f Int32
  , rootTaskSeq    :: Column f (Maybe Int32)
  , taskRefSuffix  :: Column f Text
  , title          :: Column f Text
  , description    :: Column f Text
  , notes          :: Column f Text
  , status         :: Column f Text
  , priority       :: Column f Int32
  , taskType       :: Column f Text
  , assigneeAlias  :: Column f (Maybe Text)
  , createdByAlias :: Column f (Maybe Text)
  , closedByAlias  :: Column f (Maybe Text)
  , parentTaskId   :: Column f (Maybe UUID)
  , createdAt      :: Column f UTCTime
  , updatedAt      :: Column f (Maybe UTCTime)
  , closedAt       :: Column f (Maybe UTCTime)
  , deletedAt      :: Column f (Maybe UTCTime)
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (Task f)

taskSchema :: TableSchema (Task Name)
taskSchema = TableSchema
  { name = "tasks"
  , columns = Task
      { taskId         = "task_id"
      , teamId         = "team_id"
      , taskNumber     = "task_number"
      , rootTaskSeq    = "root_task_seq"
      , taskRefSuffix  = "task_ref_suffix"
      , title          = "title"
      , description    = "description"
      , notes          = "notes"
      , status         = "status"
      , priority       = "priority"
      , taskType       = "task_type"
      , assigneeAlias  = "assignee_alias"
      , createdByAlias = "created_by_alias"
      , closedByAlias  = "closed_by_alias"
      , parentTaskId   = "parent_task_id"
      , createdAt      = "created_at"
      , updatedAt      = "updated_at"
      , closedAt       = "closed_at"
      , deletedAt      = "deleted_at"
      }
  }

------------------------------------------------------------------------
-- Task Comments
------------------------------------------------------------------------

data TaskComment f = TaskComment
  { commentId   :: Column f UUID
  , taskId      :: Column f UUID
  , teamId      :: Column f Text
  , authorAlias :: Column f Text
  , body        :: Column f Text
  , createdAt   :: Column f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (TaskComment f)

taskCommentSchema :: TableSchema (TaskComment Name)
taskCommentSchema = TableSchema
  { name = "task_comments"
  , columns = TaskComment
      { commentId   = "comment_id"
      , taskId      = "task_id"
      , teamId      = "team_id"
      , authorAlias = "author_alias"
      , body        = "body"
      , createdAt   = "created_at"
      }
  }

------------------------------------------------------------------------
-- Task Dependencies
------------------------------------------------------------------------

data TaskDependency f = TaskDependency
  { taskId      :: Column f UUID
  , dependsOnId :: Column f UUID
  , teamId      :: Column f Text
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (TaskDependency f)

taskDependencySchema :: TableSchema (TaskDependency Name)
taskDependencySchema = TableSchema
  { name = "task_dependencies"
  , columns = TaskDependency
      { taskId      = "task_id"
      , dependsOnId = "depends_on_id"
      , teamId      = "team_id"
      }
  }

------------------------------------------------------------------------
-- Reservations
------------------------------------------------------------------------

data Reservation f = Reservation
  { teamId        :: Column f Text
  , resourceKey   :: Column f Text
  , holderAlias   :: Column f Text
  , holderAgentId :: Column f UUID
  , acquiredAt    :: Column f UTCTime
  , expiresAt     :: Column f (Maybe UTCTime)
  , metadataJson  :: Column f (Maybe Text)
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (Reservation f)

reservationSchema :: TableSchema (Reservation Name)
reservationSchema = TableSchema
  { name = "reservations"
  , columns = Reservation
      { teamId        = "team_id"
      , resourceKey   = "resource_key"
      , holderAlias   = "holder_alias"
      , holderAgentId = "holder_agent_id"
      , acquiredAt    = "acquired_at"
      , expiresAt     = "expires_at"
      , metadataJson  = "metadata_json"
      }
  }

------------------------------------------------------------------------
-- Team Roles
------------------------------------------------------------------------

data TeamRole f = TeamRole
  { teamRoleId     :: Column f UUID
  , teamId         :: Column f Text
  , version        :: Column f Int32
  , bundleJson     :: Column f Text
  , isActive       :: Column f Bool
  , createdByAlias :: Column f (Maybe Text)
  , createdAt      :: Column f UTCTime
  , updatedAt      :: Column f (Maybe UTCTime)
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (TeamRole f)

teamRoleSchema :: TableSchema (TeamRole Name)
teamRoleSchema = TableSchema
  { name = "team_roles"
  , columns = TeamRole
      { teamRoleId     = "id"
      , teamId         = "team_id"
      , version        = "version"
      , bundleJson     = "bundle_json"
      , isActive       = "is_active"
      , createdByAlias = "created_by_alias"
      , createdAt      = "created_at"
      , updatedAt      = "updated_at"
      }
  }

------------------------------------------------------------------------
-- Team Instructions
------------------------------------------------------------------------

data TeamInstruction f = TeamInstruction
  { teamInstructionId :: Column f UUID
  , teamId            :: Column f Text
  , version           :: Column f Int32
  , documentJson      :: Column f Text
  , isActive          :: Column f Bool
  , createdByAlias    :: Column f (Maybe Text)
  , createdAt         :: Column f UTCTime
  , updatedAt         :: Column f (Maybe UTCTime)
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (TeamInstruction f)

teamInstructionSchema :: TableSchema (TeamInstruction Name)
teamInstructionSchema = TableSchema
  { name = "team_instructions"
  , columns = TeamInstruction
      { teamInstructionId = "id"
      , teamId            = "team_id"
      , version           = "version"
      , documentJson      = "document_json"
      , isActive          = "is_active"
      , createdByAlias    = "created_by_alias"
      , createdAt         = "created_at"
      , updatedAt         = "updated_at"
      }
  }

------------------------------------------------------------------------
-- Repos
------------------------------------------------------------------------

data Repo f = Repo
  { repoId          :: Column f UUID
  , teamId          :: Column f Text
  , originUrl       :: Column f Text
  , canonicalOrigin :: Column f Text
  , repoName        :: Column f Text
  , createdAt       :: Column f UTCTime
  , deletedAt       :: Column f (Maybe UTCTime)
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (Repo f)

repoSchema :: TableSchema (Repo Name)
repoSchema = TableSchema
  { name = "repos"
  , columns = Repo
      { repoId          = "id"
      , teamId          = "team_id"
      , originUrl       = "origin_url"
      , canonicalOrigin = "canonical_origin"
      , repoName        = "name"
      , createdAt       = "created_at"
      , deletedAt       = "deleted_at"
      }
  }

------------------------------------------------------------------------
-- Task Claims
------------------------------------------------------------------------

data TaskClaim f = TaskClaim
  { taskClaimId  :: Column f UUID
  , teamId       :: Column f Text
  , workspaceId  :: Column f UUID
  , alias        :: Column f Text
  , humanName    :: Column f Text
  , taskRef      :: Column f Text
  , apexTaskRef  :: Column f (Maybe Text)
  , claimedAt    :: Column f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (TaskClaim f)

taskClaimSchema :: TableSchema (TaskClaim Name)
taskClaimSchema = TableSchema
  { name = "task_claims"
  , columns = TaskClaim
      { taskClaimId  = "id"
      , teamId       = "team_id"
      , workspaceId  = "workspace_id"
      , alias        = "alias"
      , humanName    = "human_name"
      , taskRef      = "task_ref"
      , apexTaskRef  = "apex_task_ref"
      , claimedAt    = "claimed_at"
      }
  }

------------------------------------------------------------------------
-- Chat Sessions
------------------------------------------------------------------------

data ChatSession f = ChatSession
  { sessionId     :: Column f UUID
  , teamId        :: Column f (Maybe Text)
  , createdBy     :: Column f Text
  , waitSeconds   :: Column f (Maybe Int32)
  , waitStartedAt :: Column f (Maybe UTCTime)
  , waitStartedBy :: Column f (Maybe UUID)
  , createdAt     :: Column f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (ChatSession f)

chatSessionSchema :: TableSchema (ChatSession Name)
chatSessionSchema = TableSchema
  { name = "chat_sessions"
  , columns = ChatSession
      { sessionId     = "session_id"
      , teamId        = "team_id"
      , createdBy     = "created_by"
      , waitSeconds   = "wait_seconds"
      , waitStartedAt = "wait_started_at"
      , waitStartedBy = "wait_started_by"
      , createdAt     = "created_at"
      }
  }

------------------------------------------------------------------------
-- Chat Participants
------------------------------------------------------------------------

data ChatParticipant f = ChatParticipant
  { sessionId :: Column f UUID
  , did       :: Column f Text
  , agentId   :: Column f (Maybe UUID)
  , alias     :: Column f Text
  , address   :: Column f (Maybe Text)
  , joinedAt  :: Column f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (ChatParticipant f)

chatParticipantSchema :: TableSchema (ChatParticipant Name)
chatParticipantSchema = TableSchema
  { name = "chat_participants"
  , columns = ChatParticipant
      { sessionId = "session_id"
      , did       = "did"
      , agentId   = "agent_id"
      , alias     = "alias"
      , address   = "address"
      , joinedAt  = "joined_at"
      }
  }

------------------------------------------------------------------------
-- Chat Messages
------------------------------------------------------------------------

data ChatMessage f = ChatMessage
  { messageId     :: Column f UUID
  , sessionId     :: Column f UUID
  , fromAgentId   :: Column f (Maybe UUID)
  , fromDid       :: Column f Text
  , fromAlias     :: Column f Text
  , fromAddress   :: Column f (Maybe Text)
  , body          :: Column f Text
  , replyTo       :: Column f (Maybe UUID)
  , senderLeaving :: Column f Bool
  , hangOn        :: Column f Bool
  , signature     :: Column f (Maybe Text)
  , signedPayload :: Column f (Maybe Text)
  , createdAt     :: Column f UTCTime
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance f ~ Result => Show (ChatMessage f)

chatMessageSchema :: TableSchema (ChatMessage Name)
chatMessageSchema = TableSchema
  { name = "chat_messages"
  , columns = ChatMessage
      { messageId     = "message_id"
      , sessionId     = "session_id"
      , fromAgentId   = "from_agent_id"
      , fromDid       = "from_did"
      , fromAlias     = "from_alias"
      , fromAddress   = "from_address"
      , body          = "body"
      , replyTo       = "reply_to"
      , senderLeaving = "sender_leaving"
      , hangOn        = "hang_on"
      , signature     = "signature"
      , signedPayload = "signed_payload"
      , createdAt     = "created_at"
      }
  }
