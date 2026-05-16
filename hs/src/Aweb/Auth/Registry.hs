module Aweb.Auth.Registry
  ( KeyResolution (..)
  , resolveKey
  , newRegistryManager
  ) where

import Control.Exception (SomeException, try)
import Data.Aeson (FromJSON (..), eitherDecode, withObject, (.:))
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Generics (Generic)
import Network.HTTP.Client
  ( Manager
  , Response (..)
  , httpLbs
  , parseRequest
  , requestHeaders
  )
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types.Status (statusCode)

-- | Result of resolving a did:aw to its current did:key via the registry.
data KeyResolution = KeyResolution
  { didAw         :: Text
  , currentDIDKey :: Text
  }
  deriving stock (Show, Eq, Generic)

instance FromJSON KeyResolution where
  parseJSON = withObject "KeyResolution" $ \o ->
    KeyResolution
      <$> o .: "did_aw"
      <*> o .: "current_did_key"

-- | Resolve a did:aw identifier to its current did:key via the awid registry.
--
-- Calls GET /v1/did/{did_aw}/key on the registry.
-- Returns Nothing on network errors or non-200 responses.
resolveKey :: Manager -> Text -> Text -> IO (Maybe KeyResolution)
resolveKey manager registryUrl didAw_ = do
  let baseUrl = T.unpack (stripTrailingSlash registryUrl)
      url = baseUrl
         <> "/v1/did/"
         <> T.unpack (urlEncode didAw_)
         <> "/key"
  result <- try (doRequest url) :: IO (Either SomeException (Response LBS.ByteString))
  case result of
    Left _     -> pure Nothing
    Right resp
      | statusCode (responseStatus resp) == 200 ->
          case eitherDecode (responseBody resp) of
            Right kr -> pure (Just kr)
            Left _   -> pure Nothing
      | otherwise -> pure Nothing
  where
    doRequest :: String -> IO (Response LBS.ByteString)
    doRequest url_ = do
      initReq <- parseRequest url_
      let req = initReq { requestHeaders = [("Accept", "application/json")] }
      httpLbs req manager

-- | Create a TLS-enabled HTTP manager suitable for calling the awid registry.
newRegistryManager :: IO Manager
newRegistryManager = newTlsManager

-- | Strip a trailing slash from a URL.
stripTrailingSlash :: Text -> Text
stripTrailingSlash t
  | T.isSuffixOf "/" t = T.dropEnd 1 t
  | otherwise          = t

-- | Simple percent-encoding for the did:aw path segment.
-- Encodes ':' as %3A to be safe in URL paths.
urlEncode :: Text -> Text
urlEncode = T.concatMap encodeChar
  where
    encodeChar ':' = "%3A"
    encodeChar '/' = "%2F"
    encodeChar c   = T.singleton c
