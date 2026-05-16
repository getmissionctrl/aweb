module Aweb.Handlers.Claims
  ( claimsServer
  ) where

import Aweb.API (ClaimsAPI)
import Servant

-- | Claims endpoint handlers (stub implementation)
claimsServer :: Server ClaimsAPI
claimsServer =
       claimTask
  :<|> listClaims
  :<|> releaseClaim
  where
    claimTask _req = throwError err501
    listClaims = throwError err501
    releaseClaim _req = throwError err501
