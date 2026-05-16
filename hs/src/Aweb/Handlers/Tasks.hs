module Aweb.Handlers.Tasks
  ( tasksServer
  ) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value)
import Data.Int (Int32)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (getCurrentTime)
import Data.UUID.V4 qualified as UUID
import Rel8 qualified
import Servant

import Aweb.API (TasksAPI)
import Aweb.API.Types
  ( TaskView (..)
  , CreateTaskRequest (..)
  , UpdateTaskRequest (..)
  , ListTasksResponse (..)
  , TaskCommentView (..)
  , AddCommentRequest (..)
  , TaskRef
  )
import Aweb.Auth.Middleware (AuthIdentity (..))
import Aweb.DB (Pool, runSelect, runInsert, runUpdate, throwDB)
import Aweb.DB.Agents qualified as DB.Agents
import Aweb.DB.Schema (Agent (..), Task (..), TaskComment (..), taskSchema)
import Aweb.DB.Tasks qualified as DB.Tasks

-- | Tasks endpoint handlers with real DB calls.
tasksServer :: Pool -> AuthIdentity -> Server TasksAPI
tasksServer pool identity =
       createTask
  :<|> listTasks
  :<|> getTask
  :<|> updateTask
  :<|> deleteTask
  :<|> addComment
  :<|> listComments'
  :<|> addDep
  :<|> removeDep
  where
    -- | Resolve the calling agent from their DID key.
    resolveAgent :: Handler (Agent Rel8.Result)
    resolveAgent = do
      result <- liftIO $ runSelect pool (DB.Agents.getAgentByDID identity.didKey)
      case result of
        Left err -> throwDB err
        Right []  -> throwError err403 { errBody = "Agent not found for DID key" }
        Right (agent:_) -> pure agent

    -- | Resolve the agent's team ID from their DID key.
    resolveTeamId :: Handler Text
    resolveTeamId = do
      Agent { teamId = tid } <- resolveAgent
      pure tid

    -- | Resolve agent alias from their DID key.
    resolveAgentAlias :: Handler Text
    resolveAgentAlias = do
      Agent { alias = a } <- resolveAgent
      pure a

    -- | Parse a task ref (text like "3") into an Int32.
    parseTaskRef :: TaskRef -> Handler Int32
    parseTaskRef ref =
      case reads (T.unpack ref) of
        [(n, "")] -> pure n
        _         -> throwError err400 { errBody = "Invalid task ref: must be a number" }

    -- | Look up a task by team + number, return it or 404.
    lookupTask :: Text -> Int32 -> Handler (Task Rel8.Result)
    lookupTask teamId_ num = do
      result <- liftIO $ runSelect pool (DB.Tasks.getTaskByNumber teamId_ num)
      case result of
        Left err -> throwDB err
        Right []  -> throwError err404 { errBody = "Task not found" }
        Right (t:_) -> pure t

    -- | Convert a DB Task row to a TaskView.
    taskToView :: Task Rel8.Result -> TaskView
    taskToView t = TaskView
      { taskId         = t.taskId
      , taskNumber     = fromIntegral t.taskNumber
      , taskRefSuffix  = t.taskRefSuffix
      , title          = t.title
      , description    = t.description
      , notes          = t.notes
      , status         = t.status
      , priority       = fromIntegral t.priority
      , taskType       = t.taskType
      , assigneeAlias  = t.assigneeAlias
      , createdByAlias = t.createdByAlias
      , closedByAlias  = t.closedByAlias
      , parentTaskId   = t.parentTaskId
      , createdAt      = t.createdAt
      , updatedAt      = t.updatedAt
      , closedAt       = t.closedAt
      }

    -- | Convert a DB TaskComment row to a TaskCommentView.
    commentToView :: TaskComment Rel8.Result -> TaskCommentView
    commentToView c = TaskCommentView
      { commentId   = c.commentId
      , taskId      = c.taskId
      , authorAlias = c.authorAlias
      , body        = c.body
      , createdAt   = c.createdAt
      }

    -- | Get the next task number for a team (max existing + 1).
    nextTaskNumber :: Text -> Handler Int32
    nextTaskNumber teamId_ = do
      result <- liftIO $ runSelect pool (DB.Tasks.listTasks teamId_ Nothing Nothing)
      case result of
        Left err -> throwDB err
        Right tasks -> pure (fromIntegral (length tasks) + 1)

    -- POST /v1/tasks
    createTask :: CreateTaskRequest -> Handler TaskView
    createTask req = do
      teamId_ <- resolveTeamId
      agentAlias <- resolveAgentAlias
      newId <- liftIO UUID.nextRandom
      now <- liftIO getCurrentTime
      num <- nextTaskNumber teamId_
      let task = Task
            { taskId         = Rel8.lit newId
            , teamId         = Rel8.lit teamId_
            , taskNumber     = Rel8.lit num
            , rootTaskSeq    = Rel8.lit Nothing
            , taskRefSuffix  = Rel8.lit (T.pack (show num))
            , title          = Rel8.lit req.title
            , description    = Rel8.lit (maybe "" Prelude.id req.description)
            , notes          = Rel8.lit ""
            , status         = Rel8.lit "open"
            , priority       = Rel8.lit (maybe 0 fromIntegral req.priority)
            , taskType       = Rel8.lit (maybe "task" Prelude.id req.taskType)
            , assigneeAlias  = Rel8.lit req.assigneeAlias
            , createdByAlias = Rel8.lit (Just agentAlias)
            , closedByAlias  = Rel8.lit Nothing
            , parentTaskId   = Rel8.lit Nothing
            , createdAt      = Rel8.lit now
            , updatedAt      = Rel8.lit Nothing
            , closedAt       = Rel8.lit Nothing
            , deletedAt      = Rel8.lit Nothing
            }
      insertResult <- liftIO $ runInsert pool (DB.Tasks.insertTask task)
      case insertResult of
        Left err -> throwDB err
        Right () -> pure TaskView
          { taskId         = newId
          , taskNumber     = fromIntegral num
          , taskRefSuffix  = T.pack (show num)
          , title          = req.title
          , description    = maybe "" Prelude.id req.description
          , notes          = ""
          , status         = "open"
          , priority       = maybe 0 Prelude.id req.priority
          , taskType       = maybe "task" Prelude.id req.taskType
          , assigneeAlias  = req.assigneeAlias
          , createdByAlias = Just agentAlias
          , closedByAlias  = Nothing
          , parentTaskId   = Nothing
          , createdAt      = now
          , updatedAt      = Nothing
          , closedAt       = Nothing
          }

    -- GET /v1/tasks?status=...&assignee=...
    listTasks :: Maybe Text -> Maybe Text -> Handler ListTasksResponse
    listTasks mStatus mAssignee = do
      teamId_ <- resolveTeamId
      result <- liftIO $ runSelect pool (DB.Tasks.listTasks teamId_ mStatus mAssignee)
      case result of
        Left err -> throwDB err
        Right tasks -> pure ListTasksResponse
          { teamId = teamId_
          , tasks  = map taskToView tasks
          }

    -- GET /v1/tasks/:ref
    getTask :: TaskRef -> Handler TaskView
    getTask ref = do
      teamId_ <- resolveTeamId
      num <- parseTaskRef ref
      task <- lookupTask teamId_ num
      pure (taskToView task)

    -- PATCH /v1/tasks/:ref
    updateTask :: TaskRef -> UpdateTaskRequest -> Handler TaskView
    updateTask ref req = do
      teamId_ <- resolveTeamId
      num <- parseTaskRef ref
      task <- lookupTask teamId_ num
      now <- liftIO getCurrentTime
      -- Build an inline update for all mutable fields
      let updateStmt = Rel8.Update
            { target = taskSchema
            , from = pure ()
            , set = \_ row -> Task
                { taskId        = row.taskId
                , teamId        = row.teamId
                , taskNumber    = row.taskNumber
                , rootTaskSeq   = row.rootTaskSeq
                , taskRefSuffix = row.taskRefSuffix
                , title         = maybe row.title Rel8.lit req.title
                , description   = maybe row.description Rel8.lit req.description
                , notes         = maybe row.notes Rel8.lit req.notes
                , status        = maybe row.status Rel8.lit req.status
                , priority      = maybe row.priority (Rel8.lit . fromIntegral) req.priority
                , taskType      = row.taskType
                , assigneeAlias = case req.assigneeAlias of
                    Nothing -> row.assigneeAlias
                    Just a  -> Rel8.lit (Just a)
                , createdByAlias = row.createdByAlias
                , closedByAlias  = row.closedByAlias
                , parentTaskId   = row.parentTaskId
                , createdAt      = row.createdAt
                , updatedAt      = Rel8.lit (Just now)
                , closedAt       = row.closedAt
                , deletedAt      = row.deletedAt
                }
            , updateWhere = \_ row -> row.taskId Rel8.==. Rel8.lit task.taskId
            , returning = Rel8.NoReturning
            }
      updateResult <- liftIO $ runUpdate pool updateStmt
      case updateResult of
        Left err -> throwDB err
        Right () -> do
          -- Re-fetch the updated task
          updated <- lookupTask teamId_ num
          pure (taskToView updated)

    -- DELETE /v1/tasks/:ref
    deleteTask :: TaskRef -> Handler NoContent
    deleteTask ref = do
      teamId_ <- resolveTeamId
      num <- parseTaskRef ref
      task <- lookupTask teamId_ num
      now <- liftIO getCurrentTime
      -- Soft-delete by setting deletedAt
      let deleteStmt = Rel8.Update
            { target = taskSchema
            , from = pure ()
            , set = \_ row -> Task
                { taskId        = row.taskId
                , teamId        = row.teamId
                , taskNumber    = row.taskNumber
                , rootTaskSeq   = row.rootTaskSeq
                , taskRefSuffix = row.taskRefSuffix
                , title         = row.title
                , description   = row.description
                , notes         = row.notes
                , status        = row.status
                , priority      = row.priority
                , taskType      = row.taskType
                , assigneeAlias = row.assigneeAlias
                , createdByAlias = row.createdByAlias
                , closedByAlias  = row.closedByAlias
                , parentTaskId   = row.parentTaskId
                , createdAt      = row.createdAt
                , updatedAt      = row.updatedAt
                , closedAt       = row.closedAt
                , deletedAt      = Rel8.lit (Just now)
                }
            , updateWhere = \_ row -> row.taskId Rel8.==. Rel8.lit task.taskId
            , returning = Rel8.NoReturning
            }
      deleteResult <- liftIO $ runUpdate pool deleteStmt
      case deleteResult of
        Left err -> throwDB err
        Right () -> pure NoContent

    -- POST /v1/tasks/:ref/comments
    addComment :: TaskRef -> AddCommentRequest -> Handler TaskCommentView
    addComment ref req = do
      teamId_ <- resolveTeamId
      agentAlias <- resolveAgentAlias
      num <- parseTaskRef ref
      task <- lookupTask teamId_ num
      newId <- liftIO UUID.nextRandom
      now <- liftIO getCurrentTime
      let comment = TaskComment
            { commentId   = Rel8.lit newId
            , taskId      = Rel8.lit task.taskId
            , teamId      = Rel8.lit teamId_
            , authorAlias = Rel8.lit agentAlias
            , body        = Rel8.lit req.body
            , createdAt   = Rel8.lit now
            }
      insertResult <- liftIO $ runInsert pool (DB.Tasks.insertComment comment)
      case insertResult of
        Left err -> throwDB err
        Right () -> pure TaskCommentView
          { commentId   = newId
          , taskId      = task.taskId
          , authorAlias = agentAlias
          , body        = req.body
          , createdAt   = now
          }

    -- GET /v1/tasks/:ref/comments
    listComments' :: TaskRef -> Handler [TaskCommentView]
    listComments' ref = do
      teamId_ <- resolveTeamId
      num <- parseTaskRef ref
      task <- lookupTask teamId_ num
      result <- liftIO $ runSelect pool (DB.Tasks.listComments task.taskId)
      case result of
        Left err -> throwDB err
        Right comments -> pure (map commentToView comments)

    -- POST /v1/tasks/:ref/deps
    addDep :: TaskRef -> Value -> Handler NoContent
    addDep _ref _body = pure NoContent

    -- DELETE /v1/tasks/:ref/deps/:dep_ref
    removeDep :: TaskRef -> TaskRef -> Handler NoContent
    removeDep _ref _depRef = pure NoContent
