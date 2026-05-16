module Aweb.Handlers.Tasks
  ( tasksServer
  ) where

import Aweb.API (TasksAPI)
import Servant

-- | Tasks endpoint handlers (stub implementation)
tasksServer :: Server TasksAPI
tasksServer =
       createTask
  :<|> listTasks
  :<|> getTask
  :<|> updateTask
  :<|> deleteTask
  :<|> addComment
  :<|> listComments
  :<|> addDep
  :<|> removeDep
  where
    createTask _req = throwError err501
    listTasks _status _assignee = throwError err501
    getTask _ref = throwError err501
    updateTask _ref _req = throwError err501
    deleteTask _ref = throwError err501
    addComment _ref _req = throwError err501
    listComments _ref = throwError err501
    addDep _ref _body = throwError err501
    removeDep _ref _depRef = throwError err501
