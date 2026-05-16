module Aweb.DB.Workspaces
  ( listWorkspaces
  , getWorkspace
  , insertWorkspace
  , updateLastSeen
  , softDeleteWorkspace
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Rel8

import Aweb.DB.Schema (Workspace (..), workspaceSchema)

-- | List all non-deleted workspaces for a team.
listWorkspaces :: Text -> Query (Workspace Expr)
listWorkspaces teamId_ = do
  ws <- each workspaceSchema
  where_ $ ws.teamId ==. lit teamId_
  where_ $ isNull ws.deletedAt
  pure ws

-- | Get a workspace by ID.
getWorkspace :: UUID -> Query (Workspace Expr)
getWorkspace wsId = do
  ws <- each workspaceSchema
  where_ $ ws.workspaceId ==. lit wsId
  where_ $ isNull ws.deletedAt
  pure ws

-- | Insert a new workspace.
insertWorkspace :: Workspace Expr -> Insert ()
insertWorkspace ws = Insert
  { into = workspaceSchema
  , rows = values [ws]
  , onConflict = Abort
  , returning = NoReturning
  }

-- | Update the last-seen timestamp for a workspace.
updateLastSeen :: UUID -> UTCTime -> Update ()
updateLastSeen wsId ts = Update
  { target = workspaceSchema
  , from = pure ()
  , set = \_ ws -> ws { lastSeenAt = lit (Just ts) }
  , updateWhere = \_ ws -> ws.workspaceId ==. lit wsId
  , returning = NoReturning
  }

-- | Soft-delete a workspace by setting deletedAt.
softDeleteWorkspace :: UUID -> UTCTime -> Update ()
softDeleteWorkspace wsId ts = Update
  { target = workspaceSchema
  , from = pure ()
  , set = \_ ws -> ws { deletedAt = lit (Just ts) }
  , updateWhere = \_ ws -> ws.workspaceId ==. lit wsId
  , returning = NoReturning
  }
