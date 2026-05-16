module Aweb.Handlers.Repos
  ( reposServer
  ) where

import Aweb.API (ReposAPI)
import Servant

-- | Repos endpoint handlers (stub implementation)
reposServer :: Server ReposAPI
reposServer =
       registerRepo
  :<|> listRepos
  :<|> getRepo
  where
    registerRepo _req = throwError err501
    listRepos = throwError err501
    getRepo _repoId = throwError err501
