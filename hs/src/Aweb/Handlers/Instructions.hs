module Aweb.Handlers.Instructions
  ( instructionsServer
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

import Aweb.API (InstructionsAPI)
import Aweb.API.Types
  ( CreateInstructionVersionRequest (..)
  , InstructionVersionView (..)
  )
import Aweb.Auth.Middleware (AuthIdentity (..))
import Aweb.DB (Pool, runSelect, runInsert, runUpdate, throwDB)
import Aweb.DB.Agents qualified as DB.Agents
import Aweb.DB.Schema (Agent (..), TeamInstruction (..), teamInstructionSchema)
import Aweb.DB.TeamConfig qualified as DB.TeamConfig
import Servant

-- | Instructions endpoint handlers with real DB calls.
instructionsServer :: Pool -> AuthIdentity -> Server InstructionsAPI
instructionsServer pool identity =
       createInstructionVersion
  :<|> listInstructionVersionsHandler
  :<|> getActiveInstructionHandler
  :<|> activateInstruction
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

    -- | Convert a DB TeamInstruction to an InstructionVersionView.
    instructionToView :: TeamInstruction Rel8.Result -> InstructionVersionView
    instructionToView inst = InstructionVersionView
      { id             = inst.teamInstructionId
      , teamId         = inst.teamId
      , version        = fromIntegral inst.version
      , documentJson   = decodeJson inst.documentJson
      , isActive       = inst.isActive
      , createdByAlias = inst.createdByAlias
      , createdAt      = inst.createdAt
      }

    -- | Create a new instruction version.
    createInstructionVersion :: CreateInstructionVersionRequest -> Handler InstructionVersionView
    createInstructionVersion req = do
      agent <- lookupAgent
      newId <- liftIO UUID.nextRandom
      now <- liftIO getCurrentTime
      -- Determine next version number
      existingResult <- liftIO $ runSelect pool (DB.TeamConfig.listInstructionVersions agent.teamId)
      nextVersion <- case existingResult of
        Left err -> throwDB err
        Right insts -> pure (fromIntegral (length insts + 1) :: Int32)
      let instExpr = Rel8.lit TeamInstruction
            { teamInstructionId = newId
            , teamId            = agent.teamId
            , version           = nextVersion
            , documentJson      = encodeJson req.documentJson
            , isActive          = False
            , createdByAlias    = Just agent.alias
            , createdAt         = now
            , updatedAt         = Nothing
            }
      insertResult <- liftIO $ runInsert pool (DB.TeamConfig.insertInstructionVersion instExpr)
      case insertResult of
        Left err -> throwDB err
        Right () -> pure InstructionVersionView
          { id             = newId
          , teamId         = agent.teamId
          , version        = fromIntegral nextVersion
          , documentJson   = req.documentJson
          , isActive       = False
          , createdByAlias = Just agent.alias
          , createdAt      = now
          }

    -- | List all instruction versions for the team.
    listInstructionVersionsHandler :: Handler [InstructionVersionView]
    listInstructionVersionsHandler = do
      agent <- lookupAgent
      result <- liftIO $ runSelect pool (DB.TeamConfig.listInstructionVersions agent.teamId)
      case result of
        Left err -> throwDB err
        Right insts -> pure (map instructionToView insts)

    -- | Get the currently active instruction version.
    getActiveInstructionHandler :: Handler InstructionVersionView
    getActiveInstructionHandler = do
      agent <- lookupAgent
      result <- liftIO $ runSelect pool (DB.TeamConfig.getActiveInstruction agent.teamId)
      case result of
        Left err -> throwDB err
        Right [] -> throwError err404 { errBody = "No active instruction version" }
        Right (inst:_) -> pure (instructionToView inst)

    -- | Activate a specific instruction version (deactivates all others).
    activateInstruction :: Int -> Handler InstructionVersionView
    activateInstruction ver = do
      agent <- lookupAgent
      now <- liftIO getCurrentTime
      -- Deactivate all versions for this team
      let deactivateAll = Rel8.Update
            { target = teamInstructionSchema
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
            { target = teamInstructionSchema
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
      fetchResult <- liftIO $ runSelect pool (DB.TeamConfig.getActiveInstruction agent.teamId)
      case fetchResult of
        Left err -> throwDB err
        Right [] -> throwError err404 { errBody = "Instruction version not found" }
        Right (inst:_) -> pure (instructionToView inst)
