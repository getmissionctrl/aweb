module Aweb.Auth.DIDSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as T

import Aweb.Auth.DID (parseDIDKey, computeDIDKey, computeStableId)

spec :: Spec
spec = do
  describe "parseDIDKey" $ do
    it "rejects invalid prefix" $ do
      parseDIDKey "not-a-did" `shouldSatisfy` isLeft

    it "rejects truncated key" $ do
      parseDIDKey "did:key:z6Mkk7yq" `shouldSatisfy` isLeft

    it "round-trips with computeDIDKey" $ do
      let testDID = "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK"
      case parseDIDKey testDID of
        Left err -> expectationFailure $ "parse failed: " <> show err
        Right pk -> computeDIDKey pk `shouldBe` testDID

  describe "computeStableId" $ do
    it "produces did:aw: prefix" $ do
      let testDID = "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK"
      case parseDIDKey testDID of
        Left err -> expectationFailure $ "parse failed: " <> show err
        Right pk -> do
          let stableId = computeStableId pk
          stableId `shouldSatisfy` T.isPrefixOf "did:aw:"

isLeft :: Either a b -> Bool
isLeft (Left _)  = True
isLeft (Right _) = False
