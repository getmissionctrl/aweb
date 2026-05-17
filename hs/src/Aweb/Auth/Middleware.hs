module Aweb.Auth.Middleware
  ( AuthIdentity (..)
  , authHandler
  ) where

import Aweb.Auth.DID (computeDIDKey, computeStableId, parseDIDKey)
import Aweb.Auth.Registry (KeyResolution (..), resolveKey)
import Aweb.Auth.Signing (canonicalJSON, verifyRequestSignature)
import Control.Monad.IO.Class (liftIO)
import Crypto.Hash (SHA256, Digest, hash)
import Data.ByteArray (convert)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base64 qualified as B64
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (getCurrentTime, diffUTCTime, UTCTime)
import Data.Time.Format (parseTimeM, defaultTimeLocale)
import Data.Word (Word8)
import Network.HTTP.Client (Manager)
import Network.HTTP.Types (hAuthorization)
import Network.Wai (Request, getRequestBodyChunk, requestHeaders)
import Servant (Handler, err401, errBody, throwError)
import Servant.Server.Experimental.Auth (AuthHandler, mkAuthHandler)

-- | Authenticated identity extracted from a verified DIDKey request.
data AuthIdentity = AuthIdentity
  { didKey  :: Text
  , didAw   :: Text
  , address :: Maybe Text
  }
  deriving stock (Show, Eq)

-- | Maximum clock skew allowed between client and server (5 minutes).
maxClockSkewSeconds :: Double
maxClockSkewSeconds = 300

-- | Create a Servant auth handler that verifies DIDKey signatures
-- and optionally resolves identity via the awid registry.
authHandler :: Manager -> Text -> AuthHandler Request AuthIdentity
authHandler registryManager registryUrl = mkAuthHandler handler
  where
    handler :: Request -> Handler AuthIdentity
    handler req = do
      -- Parse Authorization header: "DIDKey <did:key:z...> <base64-signature>"
      authHeader <- case lookup hAuthorization (requestHeaders req) of
        Nothing -> throwError err401 { errBody = "Missing Authorization header" }
        Just h  -> pure (TE.decodeUtf8 h)

      (didKeyText, sigB64) <- case parseDIDKeyAuth authHeader of
        Nothing -> throwError err401 { errBody = "Invalid Authorization header format" }
        Just x  -> pure x

      -- Parse the DID key to get the public key
      pubKey <- case parseDIDKey didKeyText of
        Left e  -> throwError err401 { errBody = LBS.fromStrict (TE.encodeUtf8 ("Invalid DID key: " <> e)) }
        Right k -> pure k

      -- Parse X-AWEB-Timestamp header
      timestamp <- case lookup "X-AWEB-Timestamp" (requestHeaders req) of
        Nothing -> throwError err401 { errBody = "Missing X-AWEB-Timestamp header" }
        Just ts -> pure (TE.decodeUtf8 ts)

      -- Enforce clock skew
      now <- liftIO getCurrentTime
      case parseTimestamp timestamp of
        Nothing -> throwError err401 { errBody = "Invalid timestamp format" }
        Just t  ->
          let skew = abs (realToFrac (diffUTCTime now t) :: Double)
          in if skew > maxClockSkewSeconds
               then throwError err401 { errBody = "Timestamp outside acceptable skew" }
               else pure ()

      -- Read request body and compute SHA256
      body <- liftIO (consumeRequestBody req)
      let bodyHash = computeBodySHA256 body

      -- Compute the stable identity (did:aw)
      let stableId = computeStableId pubKey

      -- Build canonical signing payload
      let payload = canonicalJSON
            [ ("body_sha256", bodyHash)
            , ("did_aw", stableId)
            , ("timestamp", timestamp)
            ]

      -- Decode the base64 signature (RFC 4648, no padding)
      sigBytes <- case B64.decode (padBase64 (TE.encodeUtf8 sigB64)) of
        Left _  -> throwError err401 { errBody = "Invalid signature encoding" }
        Right s -> pure s

      -- Verify the Ed25519 signature
      if not (verifyRequestSignature pubKey sigBytes payload)
        then throwError err401 { errBody = "Signature verification failed" }
        else pure ()

      -- Resolve identity via registry: check the presented did:key is
      -- still the current key for this did:aw (detects key rotation).
      -- If the registry is unavailable we allow the request through —
      -- the signature is valid regardless.
      liftIO (resolveKey registryManager registryUrl stableId) >>= \case
        Just kr
          | kr.currentDIDKey /= didKeyText ->
              throwError err401
                { errBody = LBS.fromStrict $ TE.encodeUtf8 $
                    "Key rotated: presented " <> didKeyText
                    <> " but registry says current key is " <> kr.currentDIDKey
                }
        _ -> pure () -- registry unavailable or key matches — allow

      pure AuthIdentity
        { didKey  = didKeyText
        , didAw   = stableId
        , address = lookupAddress req
        }

-- | Parse "DIDKey <did:key:z...> <signature>" from the Authorization header.
parseDIDKeyAuth :: Text -> Maybe (Text, Text)
parseDIDKeyAuth header = do
  let stripped = T.strip header
  rest <- T.stripPrefix "DIDKey " stripped
  let parts = T.words rest
  case parts of
    [didKey_, sig_] -> Just (didKey_, sig_)
    _               -> Nothing

-- | Parse an RFC3339 timestamp.
parseTimestamp :: Text -> Maybe UTCTime
parseTimestamp ts =
  let s = T.unpack ts
  in case parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%S%Z" s of
       Just t  -> Just t
       Nothing -> parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%S%Q%Z" s

-- | Compute SHA256 hex digest of the request body.
computeBodySHA256 :: ByteString -> Text
computeBodySHA256 body =
  let digest = hash body :: Digest SHA256
      digestBS = convert digest :: ByteString
  in TE.decodeUtf8 (toHex digestBS)

-- | Convert bytes to lowercase hex.
toHex :: ByteString -> ByteString
toHex = BS.concatMap (\w ->
  let hi = w `div` 16
      lo = w `mod` 16
  in BS.pack [hexDigit hi, hexDigit lo])
  where
    hexDigit :: Word8 -> Word8
    hexDigit n
      | n < 10    = n + 48  -- '0'
      | otherwise = n + 87  -- 'a' - 10

-- | Pad base64 string to correct length (raw base64 has no padding).
padBase64 :: ByteString -> ByteString
padBase64 bs =
  let remainder = BS.length bs `mod` 4
  in if remainder == 0
     then bs
     else bs <> BS.replicate (4 - remainder) 0x3D  -- '='

-- | Look up the X-AWEB-Address header for an optional address.
lookupAddress :: Request -> Maybe Text
lookupAddress req =
  TE.decodeUtf8 <$> lookup "X-AWEB-Address" (requestHeaders req)

-- | Read the full request body. WAI request bodies are streaming,
-- so we read all chunks.
consumeRequestBody :: Request -> IO ByteString
consumeRequestBody req = do
  ref <- newIORef BS.empty
  let loop = do
        chunk <- getRequestBodyChunk req
        if BS.null chunk
          then readIORef ref
          else do
            existing <- readIORef ref
            writeIORef ref (existing <> chunk)
            loop
  loop
