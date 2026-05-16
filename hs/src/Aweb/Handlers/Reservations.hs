module Aweb.Handlers.Reservations
  ( reservationsServer
  ) where

import Aweb.API (ReservationsAPI)
import Servant

-- | Reservations endpoint handlers (stub implementation)
reservationsServer :: Server ReservationsAPI
reservationsServer =
       acquireReservation
  :<|> listReservations
  :<|> revokeReservation
  where
    acquireReservation _req = throwError err501
    listReservations = throwError err501
    revokeReservation _req = throwError err501
