module Aweb.API.HealthSpec (spec) where

import Test.Hspec

spec :: Spec
spec = do
  describe "GET /health" $ do
    it "returns status ok (placeholder)" $ do
      "ok" `shouldBe` ("ok" :: String)
