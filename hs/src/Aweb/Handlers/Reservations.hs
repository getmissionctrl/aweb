module Aweb.Handlers.Reservations
  ( reservationsServer
  ) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value, decode, encode)
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (NominalDiffTime, addUTCTime, getCurrentTime)
import Rel8 qualified

import Aweb.API (ReservationsAPI)
import Aweb.API.Types
  ( AcquireReservationRequest (..)
  , ReservationView (..)
  , RevokeReservationRequest (..)
  )
import Aweb.Auth.Middleware (AuthIdentity (..))
import Aweb.DB (Pool, runSelect, runInsert, runDelete, throwDB)
import Aweb.DB.Agents qualified as DB.Agents
import Aweb.DB.Reservations qualified as DB.Reservations
import Aweb.DB.Schema (Agent (..), Reservation (..))
import Servant

-- | Reservations endpoint handlers with real DB calls.
reservationsServer :: Pool -> AuthIdentity -> Server ReservationsAPI
reservationsServer pool identity =
       acquireReservation
  :<|> listReservationsHandler
  :<|> revokeReservation
  where
    -- | Look up the authenticated agent by DID key.
    lookupAgent :: Handler (Agent Rel8.Result)
    lookupAgent = do
      result <- liftIO $ runSelect pool (DB.Agents.getAgentByDID identity.didKey)
      case result of
        Left err -> throwDB err
        Right [] -> throwError err403 { errBody = "Agent not registered" }
        Right (a:_) -> pure a

    -- | Decode metadata JSON text to Aeson Value.
    decodeMetadata :: Maybe Text -> Maybe Value
    decodeMetadata Nothing = Nothing
    decodeMetadata (Just t) = decode (LBS.fromStrict (TE.encodeUtf8 t))

    -- | Encode Aeson Value to metadata JSON text.
    encodeMetadata :: Maybe Value -> Maybe Text
    encodeMetadata Nothing = Nothing
    encodeMetadata (Just v) = Just (TE.decodeUtf8 (LBS.toStrict (encode v)))

    -- | Convert a DB Reservation to a ReservationView.
    reservationToView :: Reservation Rel8.Result -> ReservationView
    reservationToView res = ReservationView
      { teamId        = res.teamId
      , resourceKey   = res.resourceKey
      , holderAlias   = res.holderAlias
      , holderAgentId = res.holderAgentId
      , acquiredAt    = res.acquiredAt
      , expiresAt     = res.expiresAt
      , metadataJson  = decodeMetadata res.metadataJson
      }

    -- | Acquire a reservation for the authenticated agent.
    acquireReservation :: AcquireReservationRequest -> Handler ReservationView
    acquireReservation req = do
      agent <- lookupAgent
      now <- liftIO getCurrentTime
      let expiry = case req.expiresInSec of
            Nothing -> Nothing
            Just secs -> Just (addUTCTime (fromIntegral secs :: NominalDiffTime) now)
          metaText = encodeMetadata req.metadata
          resExpr = Rel8.lit Reservation
            { teamId        = agent.teamId
            , resourceKey   = req.resourceKey
            , holderAlias   = agent.alias
            , holderAgentId = agent.agentId
            , acquiredAt    = now
            , expiresAt     = expiry
            , metadataJson  = metaText
            }
      insertResult <- liftIO $ runInsert pool (DB.Reservations.insertReservation resExpr)
      case insertResult of
        Left err -> throwDB err
        Right () -> pure ReservationView
          { teamId        = agent.teamId
          , resourceKey   = req.resourceKey
          , holderAlias   = agent.alias
          , holderAgentId = agent.agentId
          , acquiredAt    = now
          , expiresAt     = expiry
          , metadataJson  = req.metadata
          }

    -- | List all reservations for the authenticated agent's team.
    listReservationsHandler :: Handler [ReservationView]
    listReservationsHandler = do
      agent <- lookupAgent
      result <- liftIO $ runSelect pool (DB.Reservations.listReservations agent.teamId)
      case result of
        Left err -> throwDB err
        Right rows -> pure (map reservationToView rows)

    -- | Revoke a reservation by resource key.
    revokeReservation :: RevokeReservationRequest -> Handler NoContent
    revokeReservation req = do
      agent <- lookupAgent
      delResult <- liftIO $ runDelete pool (DB.Reservations.deleteReservation agent.teamId req.resourceKey)
      case delResult of
        Left err -> throwDB err
        Right () -> pure NoContent
