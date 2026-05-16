module Aweb.Nats.AuthCallout
  ( AuthCalloutRequest (..)
  , AuthCalloutResponse (..)
  , handleAuthCallout
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)

-- | NATS auth callout request from nats-server
data AuthCalloutRequest = AuthCalloutRequest
  { clientInfo  :: ClientInfo
  , connectOpts :: ConnectOpts
  }
  deriving stock (Generic, Show)
  deriving anyclass (FromJSON)

data ClientInfo = ClientInfo
  { host :: Text
  , id   :: Int
  , name :: Maybe Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (FromJSON)

data ConnectOpts = ConnectOpts
  { user  :: Maybe Text
  , pass  :: Maybe Text
  , token :: Maybe Text
  , sig   :: Maybe Text
  , nkey  :: Maybe Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (FromJSON)

-- | NATS auth callout response
data AuthCalloutResponse = AuthCalloutResponse
  { allowed    :: Bool
  , account    :: Maybe Text
  , publish    :: AuthPermissions
  , subscribe  :: AuthPermissions
  , reason     :: Maybe Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON)

data AuthPermissions = AuthPermissions
  { allow :: [Text]
  , deny  :: [Text]
  }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON)

-- | Handle a NATS auth callout request
-- Verifies DID signature, resolves identity, returns permissions
handleAuthCallout :: AuthCalloutRequest -> IO AuthCalloutResponse
handleAuthCallout _req = do
  -- TODO: Implement DID verification and permission scoping
  -- 1. Extract DID key from connect opts (token or nkey field)
  -- 2. Verify Ed25519 signature
  -- 3. Resolve identity via awid registry
  -- 4. Look up team membership
  -- 5. Return scoped publish/subscribe permissions
  pure AuthCalloutResponse
    { allowed = False
    , account = Nothing
    , publish = AuthPermissions { allow = [], deny = [] }
    , subscribe = AuthPermissions { allow = [], deny = [] }
    , reason = Just "Auth callout not yet implemented"
    }
