module Aweb.Handlers.Repos
  ( reposServer
  ) where

import Control.Monad.IO.Class (liftIO)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Time.Clock (getCurrentTime)
import Data.UUID (UUID)
import Data.UUID.V4 qualified as UUID
import Rel8 qualified

import Aweb.API (ReposAPI)
import Aweb.API.Types
  ( RegisterRepoRequest (..)
  , RepoView (..)
  )
import Aweb.Auth.Middleware (AuthIdentity (..))
import Aweb.DB (Pool, runSelect, runInsert, throwDB)
import Aweb.DB.Agents qualified as DB.Agents
import Aweb.DB.Repos qualified as DB.Repos
import Aweb.DB.Schema (Agent (..), Repo (..))
import Servant

-- | Repos endpoint handlers with real DB calls.
reposServer :: Pool -> AuthIdentity -> Server ReposAPI
reposServer pool identity =
       registerRepo
  :<|> listReposHandler
  :<|> getRepoHandler
  where
    -- | Look up the authenticated agent by DID key.
    lookupAgent :: Handler (Agent Rel8.Result)
    lookupAgent = do
      result <- liftIO $ runSelect pool (DB.Agents.getAgentByDID identity.didKey)
      case result of
        Left err -> throwDB err
        Right [] -> throwError err403 { errBody = "Agent not registered" }
        Right (a:_) -> pure a

    -- | Convert a DB Repo to a RepoView.
    repoToView :: Repo Rel8.Result -> RepoView
    repoToView repo = RepoView
      { repoId          = repo.repoId
      , teamId          = repo.teamId
      , originUrl       = repo.originUrl
      , canonicalOrigin = repo.canonicalOrigin
      , name            = repo.repoName
      , createdAt       = repo.createdAt
      }

    -- | Derive a canonical origin from a URL (strip .git suffix, normalize).
    canonicalize :: Text -> Text
    canonicalize url = url

    -- | Register a new repo.
    registerRepo :: RegisterRepoRequest -> Handler RepoView
    registerRepo req = do
      agent <- lookupAgent
      newId <- liftIO UUID.nextRandom
      now <- liftIO getCurrentTime
      let repoName_ = fromMaybe req.originUrl req.name
          repoExpr = Rel8.lit Repo
            { repoId          = newId
            , teamId          = agent.teamId
            , originUrl       = req.originUrl
            , canonicalOrigin = canonicalize req.originUrl
            , repoName        = repoName_
            , createdAt       = now
            , deletedAt       = Nothing
            }
      insertResult <- liftIO $ runInsert pool (DB.Repos.insertRepo repoExpr)
      case insertResult of
        Left err -> throwDB err
        Right () -> pure RepoView
          { repoId          = newId
          , teamId          = agent.teamId
          , originUrl       = req.originUrl
          , canonicalOrigin = canonicalize req.originUrl
          , name            = repoName_
          , createdAt       = now
          }

    -- | List all repos for the team.
    listReposHandler :: Handler [RepoView]
    listReposHandler = do
      agent <- lookupAgent
      result <- liftIO $ runSelect pool (DB.Repos.listRepos agent.teamId)
      case result of
        Left err -> throwDB err
        Right repos -> pure (map repoToView repos)

    -- | Get a specific repo by ID.
    getRepoHandler :: UUID -> Handler RepoView
    getRepoHandler repoId_ = do
      result <- liftIO $ runSelect pool (DB.Repos.getRepo repoId_)
      case result of
        Left err -> throwDB err
        Right [] -> throwError err404 { errBody = "Repo not found" }
        Right (repo:_) -> pure (repoToView repo)
