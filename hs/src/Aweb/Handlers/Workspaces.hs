module Aweb.Handlers.Workspaces
  ( workspacesServer
  ) where

import Aweb.API (WorkspacesAPI)
import Servant

-- | Workspaces endpoint handlers (stub implementation)
workspacesServer :: Server WorkspacesAPI
workspacesServer =
       registerWorkspace
  :<|> heartbeat
  :<|> listWorkspaces
  :<|> getWorkspace
  :<|> deactivate
  :<|> deleteWorkspace
  where
    registerWorkspace _req = throwError err501
    heartbeat _req = throwError err501
    listWorkspaces = throwError err501
    getWorkspace _wsId = throwError err501
    deactivate = throwError err501
    deleteWorkspace _wsId = throwError err501
