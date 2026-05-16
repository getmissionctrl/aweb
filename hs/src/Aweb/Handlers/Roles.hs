module Aweb.Handlers.Roles
  ( rolesServer
  ) where

import Aweb.API (RolesAPI)
import Servant

-- | Roles endpoint handlers (stub implementation)
rolesServer :: Server RolesAPI
rolesServer =
       createRoleVersion
  :<|> listRoleVersions
  :<|> getActiveRole
  :<|> activateRole
  where
    createRoleVersion _req = throwError err501
    listRoleVersions = throwError err501
    getActiveRole = throwError err501
    activateRole _version = throwError err501
