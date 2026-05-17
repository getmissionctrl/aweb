module Aweb.Handlers.Roles
  ( rolesServer
  ) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value (..), decode, encode)
import Data.ByteString.Lazy qualified as LBS
import Data.Int (Int32)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (getCurrentTime)
import Data.UUID.V4 qualified as UUID
import Rel8 qualified

import Aweb.API (RolesAPI)
import Aweb.API.Types
  ( CreateRoleVersionRequest (..)
  , RoleVersionView (..)
  )
import Aweb.Auth.Middleware (AuthIdentity (..))
import Aweb.DB (Pool, runSelect, runInsert, runUpdate, throwDB)
import Aweb.DB.Agents qualified as DB.Agents
import Aweb.DB.Schema (Agent (..), TeamRole (..), teamRoleSchema)
import Aweb.DB.TeamConfig qualified as DB.TeamConfig
import Servant

-- | Roles endpoint handlers with real DB calls.
rolesServer :: Pool -> AuthIdentity -> Server RolesAPI
rolesServer pool identity =
       createRoleVersion
  :<|> listRoleVersionsHandler
  :<|> getActiveRoleHandler
  :<|> activateRole
  where
    -- | Look up the authenticated agent by DID key.
    lookupAgent :: Handler (Agent Rel8.Result)
    lookupAgent = do
      result <- liftIO $ runSelect pool (DB.Agents.getAgentByDID identity.didKey)
      case result of
        Left err -> throwDB err
        Right [] -> throwError err403 { errBody = "Agent not registered" }
        Right (a:_) -> pure a

    -- | Decode JSON text to Aeson Value.
    decodeJson :: Text -> Value
    decodeJson t = case decode (LBS.fromStrict (TE.encodeUtf8 t)) of
      Nothing -> Null
      Just v  -> v

    -- | Encode Aeson Value to JSON text.
    encodeJson :: Value -> Text
    encodeJson v = TE.decodeUtf8 (LBS.toStrict (encode v))

    -- | Convert a DB TeamRole to a RoleVersionView.
    roleToView :: TeamRole Rel8.Result -> RoleVersionView
    roleToView role = RoleVersionView
      { id             = role.teamRoleId
      , teamId         = role.teamId
      , version        = fromIntegral role.version
      , bundleJson     = decodeJson role.bundleJson
      , isActive       = role.isActive
      , createdByAlias = role.createdByAlias
      , createdAt      = role.createdAt
      }

    -- | Create a new role version.
    createRoleVersion :: CreateRoleVersionRequest -> Handler RoleVersionView
    createRoleVersion req = do
      agent <- lookupAgent
      newId <- liftIO UUID.nextRandom
      now <- liftIO getCurrentTime
      -- Determine next version number
      existingResult <- liftIO $ runSelect pool (DB.TeamConfig.listRoleVersions agent.teamId)
      nextVersion <- case existingResult of
        Left err -> throwDB err
        Right roles -> pure (fromIntegral (length roles + 1) :: Int32)
      let roleExpr = Rel8.lit TeamRole
            { teamRoleId     = newId
            , teamId         = agent.teamId
            , version        = nextVersion
            , bundleJson     = encodeJson req.bundleJson
            , isActive       = False
            , createdByAlias = Just agent.alias
            , createdAt      = now
            , updatedAt      = Nothing
            }
      insertResult <- liftIO $ runInsert pool (DB.TeamConfig.insertRoleVersion roleExpr)
      case insertResult of
        Left err -> throwDB err
        Right () -> pure RoleVersionView
          { id             = newId
          , teamId         = agent.teamId
          , version        = fromIntegral nextVersion
          , bundleJson     = req.bundleJson
          , isActive       = False
          , createdByAlias = Just agent.alias
          , createdAt      = now
          }

    -- | List all role versions for the team.
    listRoleVersionsHandler :: Handler [RoleVersionView]
    listRoleVersionsHandler = do
      agent <- lookupAgent
      result <- liftIO $ runSelect pool (DB.TeamConfig.listRoleVersions agent.teamId)
      case result of
        Left err -> throwDB err
        Right roles -> pure (map roleToView roles)

    -- | Get the currently active role version.
    getActiveRoleHandler :: Handler RoleVersionView
    getActiveRoleHandler = do
      agent <- lookupAgent
      result <- liftIO $ runSelect pool (DB.TeamConfig.getActiveRole agent.teamId)
      case result of
        Left err -> throwDB err
        Right [] -> throwError err404 { errBody = "No active role version" }
        Right (role:_) -> pure (roleToView role)

    -- | Activate a specific role version (deactivates all others).
    activateRole :: Int -> Handler RoleVersionView
    activateRole ver = do
      agent <- lookupAgent
      now <- liftIO getCurrentTime
      -- Deactivate all versions for this team
      let deactivateAll = Rel8.Update
            { target = teamRoleSchema
            , from = pure ()
            , set = \_ row -> row { isActive = Rel8.lit False, updatedAt = Rel8.lit (Just now) }
            , updateWhere = \_ row -> row.teamId Rel8.==. Rel8.lit agent.teamId
            , returning = Rel8.NoReturning
            }
      deactResult <- liftIO $ runUpdate pool deactivateAll
      case deactResult of
        Left err -> throwDB err
        Right () -> pure ()
      -- Activate the specified version
      let activateOne = Rel8.Update
            { target = teamRoleSchema
            , from = pure ()
            , set = \_ row -> row { isActive = Rel8.lit True, updatedAt = Rel8.lit (Just now) }
            , updateWhere = \_ row ->
                row.teamId Rel8.==. Rel8.lit agent.teamId
                Rel8.&&. row.version Rel8.==. Rel8.lit (fromIntegral ver :: Int32)
            , returning = Rel8.NoReturning
            }
      actResult <- liftIO $ runUpdate pool activateOne
      case actResult of
        Left err -> throwDB err
        Right () -> pure ()
      -- Fetch and return the activated version
      fetchResult <- liftIO $ runSelect pool (DB.TeamConfig.getActiveRole agent.teamId)
      case fetchResult of
        Left err -> throwDB err
        Right [] -> throwError err404 { errBody = "Role version not found" }
        Right (role:_) -> pure (roleToView role)
