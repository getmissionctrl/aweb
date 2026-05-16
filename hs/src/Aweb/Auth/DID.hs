module Aweb.Auth.DID
  ( parseDIDKey
  , computeDIDKey
  , computeStableId
  ) where

import Crypto.Error (CryptoFailable (..))
import Crypto.Hash (SHA256, Digest, hash)
import Crypto.PubKey.Ed25519 qualified as Ed25519
import Data.ByteArray (convert)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base58 (bitcoinAlphabet, encodeBase58, decodeBase58)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)

-- | Multicodec prefix for Ed25519 public keys: 0xed 0x01
ed25519MulticodecPrefix :: ByteString
ed25519MulticodecPrefix = BS.pack [0xed, 0x01]

-- | did:key prefix including the multibase 'z' indicator
didKeyPrefix :: Text
didKeyPrefix = "did:key:z"

-- | Parse a did:key:z... string to an Ed25519 public key.
--
-- Format:
--   1. Strip "did:key:z" prefix (z = multibase base58btc indicator)
--   2. Decode remaining base58btc
--   3. First 2 bytes must be 0xed 0x01 (Ed25519 multicodec)
--   4. Remaining 32 bytes are the raw public key
parseDIDKey :: Text -> Either Text Ed25519.PublicKey
parseDIDKey did
  | not (T.isPrefixOf didKeyPrefix did) =
      Left $ "invalid did:key: missing prefix " <> didKeyPrefix
  | otherwise = do
      let encoded = TE.encodeUtf8 (T.drop (T.length didKeyPrefix) did)
      decoded <- maybe (Left "invalid did:key: base58 decode failed") Right
                   (decodeBase58 bitcoinAlphabet encoded)
      let expected = 2 + 32 -- 2 bytes prefix + 32 bytes key
      if BS.length decoded /= expected
        then Left $ "invalid did:key: expected "
                  <> T.pack (show expected)
                  <> " bytes, got "
                  <> T.pack (show (BS.length decoded))
        else do
          let (prefix, keyBytes) = BS.splitAt 2 decoded
          if prefix /= ed25519MulticodecPrefix
            then Left $ "invalid did:key: expected Ed25519 multicodec 0xed01, got 0x"
                      <> T.pack (byteToHex (BS.index prefix 0))
                      <> T.pack (byteToHex (BS.index prefix 1))
            else case Ed25519.publicKey keyBytes of
                   CryptoFailed _ -> Left "invalid did:key: invalid Ed25519 public key bytes"
                   CryptoPassed pk -> Right pk

-- | Encode an Ed25519 public key as a did:key:z... string.
computeDIDKey :: Ed25519.PublicKey -> Text
computeDIDKey pub =
  let keyBytes = convert pub :: ByteString
      withPrefix = ed25519MulticodecPrefix <> keyBytes
      encoded = encodeBase58 bitcoinAlphabet withPrefix
  in "did:key:z" <> TE.decodeUtf8 encoded

-- | Derive the canonical did:aw stable identifier from an Ed25519 public key.
--
-- Algorithm: SHA-256 the 32-byte public key, take first 20 bytes, base58btc encode.
computeStableId :: Ed25519.PublicKey -> Text
computeStableId pub =
  let keyBytes = convert pub :: ByteString
      digest = hash keyBytes :: Digest SHA256
      digestBS = convert digest :: ByteString
      first20 = BS.take 20 digestBS
      encoded = encodeBase58 bitcoinAlphabet first20
  in "did:aw:" <> TE.decodeUtf8 encoded

-- | Convert a byte to two hex characters.
byteToHex :: Word8 -> String
byteToHex w = [hexChar (w `div` 16), hexChar (w `mod` 16)]
  where
    hexChar :: Word8 -> Char
    hexChar n
      | n < 10    = toEnum (fromEnum '0' + fromIntegral n)
      | otherwise = toEnum (fromEnum 'a' + fromIntegral n - 10)
