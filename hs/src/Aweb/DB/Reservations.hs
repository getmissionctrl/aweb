module Aweb.DB.Reservations
  ( listReservations
  , insertReservation
  , deleteReservation
  ) where

import Data.Text (Text)
import Rel8

import Aweb.DB.Schema (Reservation (..), reservationSchema)

-- | List all reservations for a team.
listReservations :: Text -> Query (Reservation Expr)
listReservations teamId_ = do
  res <- each reservationSchema
  where_ $ res.teamId ==. lit teamId_
  pure res

-- | Insert a new reservation.
insertReservation :: Reservation Expr -> Insert ()
insertReservation res = Insert
  { into = reservationSchema
  , rows = values [res]
  , onConflict = Abort
  , returning = NoReturning
  }

-- | Delete a reservation by team and resource key.
deleteReservation :: Text -> Text -> Delete ()
deleteReservation teamId_ resourceKey_ = Delete
  { from = reservationSchema
  , using = pure ()
  , deleteWhere = \_ res ->
      res.teamId ==. lit teamId_ &&. res.resourceKey ==. lit resourceKey_
  , returning = NoReturning
  }
