module Aweb.Auth.Signing
  ( canonicalJSON
  , verifyRequestSignature
  ) where

import Crypto.Error (CryptoFailable (..))
import Crypto.PubKey.Ed25519 qualified as Ed25519
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as Builder
import Data.ByteString.Lazy qualified as LBS
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)

-- | Build canonical JSON from a list of key-value pairs.
--
-- Produces sorted-key JSON with no whitespace, matching the Go/Python
-- implementations. All values are treated as JSON strings.
-- Example output: {"body_sha256":"abc...","did_aw":"did:aw:...","timestamp":"2024-..."}
canonicalJSON :: [(Text, Text)] -> ByteString
canonicalJSON fields =
  LBS.toStrict $ Builder.toLazyByteString $ buildObject (sortOn fst fields)
  where
    buildObject :: [(Text, Text)] -> Builder.Builder
    buildObject fs =
      Builder.char7 '{' <> mconcat (intersperse' (Builder.char7 ',') (map buildField fs)) <> Builder.char7 '}'

    buildField :: (Text, Text) -> Builder.Builder
    buildField (k, v) =
      Builder.char7 '"'
        <> escapeJSON (TE.encodeUtf8 k)
        <> Builder.char7 '"'
        <> Builder.char7 ':'
        <> Builder.char7 '"'
        <> escapeJSON (TE.encodeUtf8 v)
        <> Builder.char7 '"'

    intersperse' :: Builder.Builder -> [Builder.Builder] -> [Builder.Builder]
    intersperse' _ []     = []
    intersperse' _ [x]    = [x]
    intersperse' sep (x:xs) = x : map (sep <>) xs

-- | Escape a ByteString for JSON string content.
-- Handles: \", \\, \n, \r, \t, \b, \f, and control chars < 0x20.
escapeJSON :: ByteString -> Builder.Builder
escapeJSON = BS.foldl' (\acc w -> acc <> escapeWord8 w) mempty
  where
    escapeWord8 :: Word8 -> Builder.Builder
    escapeWord8 0x22 = Builder.byteString "\\\""  -- "
    escapeWord8 0x5C = Builder.byteString "\\\\"  -- \
    escapeWord8 0x0A = Builder.byteString "\\n"   -- newline
    escapeWord8 0x0D = Builder.byteString "\\r"   -- carriage return
    escapeWord8 0x09 = Builder.byteString "\\t"   -- tab
    escapeWord8 0x08 = Builder.byteString "\\b"   -- backspace
    escapeWord8 0x0C = Builder.byteString "\\f"   -- form feed
    escapeWord8 w
      | w < 0x20  = Builder.byteString "\\u00"
                      <> Builder.char7 (hexChar (w `div` 16))
                      <> Builder.char7 (hexChar (w `mod` 16))
      | otherwise = Builder.word8 w

    hexChar :: Word8 -> Char
    hexChar n
      | n < 10    = toEnum (fromEnum '0' + fromIntegral n)
      | otherwise = toEnum (fromEnum 'a' + fromIntegral n - 10)

-- | Verify an Ed25519 signature over a payload.
--
-- Takes the public key, the raw signature bytes, and the message bytes.
-- Returns True if the signature is valid.
verifyRequestSignature :: Ed25519.PublicKey -> ByteString -> ByteString -> Bool
verifyRequestSignature pub sigBytes message =
  case Ed25519.signature sigBytes of
    CryptoFailed _ -> False
    CryptoPassed sig -> Ed25519.verify pub message sig
