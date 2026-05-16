module Aweb.API (API, server) where

import Data.Text (Text)
import GHC.Generics (Generic)
import Data.Aeson (ToJSON)
import Servant

data HealthStatus = HealthStatus
  { status  :: Text
  , version :: Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON)

type API = "health" :> Get '[JSON] HealthStatus

server :: Server API
server = pure HealthStatus { status = "ok", version = "0.1.0" }
