module Aweb.Auth.SigningSpec (spec) where

import Test.Hspec
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BS8

import Aweb.Auth.Signing (canonicalJSON)

spec :: Spec
spec = do
  describe "canonicalJSON" $ do
    it "sorts keys alphabetically" $ do
      let result = canonicalJSON
            [ ("timestamp", "2024-01-01T00:00:00Z")
            , ("body_sha256", "abc123")
            , ("did_aw", "did:aw:test")
            ]
      result `shouldBe` "{\"body_sha256\":\"abc123\",\"did_aw\":\"did:aw:test\",\"timestamp\":\"2024-01-01T00:00:00Z\"}"

    it "produces no whitespace" $ do
      let result = canonicalJSON [("key", "value")]
      BS8.elem ' ' result `shouldBe` False
      BS8.elem '\n' result `shouldBe` False
