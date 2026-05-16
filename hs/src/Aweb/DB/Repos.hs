module Aweb.DB.Repos
  ( listRepos
  , getRepo
  , insertRepo
  ) where

import Data.Text (Text)
import Data.UUID (UUID)
import Rel8

import Aweb.DB.Schema (Repo (..), repoSchema)

-- | List all non-deleted repos for a team.
listRepos :: Text -> Query (Repo Expr)
listRepos teamId_ = do
  repo <- each repoSchema
  where_ $ repo.teamId ==. lit teamId_
  where_ $ isNull repo.deletedAt
  pure repo

-- | Get a repo by ID.
getRepo :: UUID -> Query (Repo Expr)
getRepo repoId_ = do
  repo <- each repoSchema
  where_ $ repo.repoId ==. lit repoId_
  where_ $ isNull repo.deletedAt
  pure repo

-- | Insert a new repo.
insertRepo :: Repo Expr -> Insert ()
insertRepo repo = Insert
  { into = repoSchema
  , rows = values [repo]
  , onConflict = Abort
  , returning = NoReturning
  }
