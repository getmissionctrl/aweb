module Aweb.DB.Tasks
  ( listTasks
  , getTaskByNumber
  , insertTask
  , updateTaskStatus
  , listComments
  , insertComment
  ) where

import Data.Int (Int32)
import Data.Text (Text)
import Data.UUID (UUID)
import Rel8

import Aweb.DB.Schema (Task (..), taskSchema, TaskComment (..), taskCommentSchema)

-- | List tasks for a team, with optional status and assignee filters.
listTasks :: Text -> Maybe Text -> Maybe Text -> Query (Task Expr)
listTasks teamId_ mStatus mAssignee = do
  task <- each taskSchema
  where_ $ task.teamId ==. lit teamId_
  where_ $ isNull task.deletedAt
  maybe (pure ()) (\s -> where_ $ task.status ==. lit s) mStatus
  maybe (pure ()) (\a -> where_ $ task.assigneeAlias ==. lit (Just a)) mAssignee
  pure task

-- | Get a task by team and task number.
getTaskByNumber :: Text -> Int32 -> Query (Task Expr)
getTaskByNumber teamId_ num = do
  task <- each taskSchema
  where_ $ task.teamId ==. lit teamId_
  where_ $ task.taskNumber ==. lit num
  where_ $ isNull task.deletedAt
  pure task

-- | Insert a new task row.
insertTask :: Task Expr -> Insert ()
insertTask task = Insert
  { into = taskSchema
  , rows = values [task]
  , onConflict = Abort
  , returning = NoReturning
  }

-- | Update task status by task ID.
updateTaskStatus :: UUID -> Text -> Update ()
updateTaskStatus taskId_ newStatus = Update
  { target = taskSchema
  , from = pure ()
  , set = \_ task -> task { status = lit newStatus }
  , updateWhere = \_ task -> task.taskId ==. lit taskId_
  , returning = NoReturning
  }

-- | List comments for a task.
listComments :: UUID -> Query (TaskComment Expr)
listComments taskId_ = do
  comment <- each taskCommentSchema
  where_ $ comment.taskId ==. lit taskId_
  pure comment

-- | Insert a new task comment.
insertComment :: TaskComment Expr -> Insert ()
insertComment comment = Insert
  { into = taskCommentSchema
  , rows = values [comment]
  , onConflict = Abort
  , returning = NoReturning
  }
