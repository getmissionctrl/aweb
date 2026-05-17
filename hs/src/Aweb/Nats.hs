module Aweb.Nats
  ( NatsEnv (..)
  , connectNats
  , disconnectNats
  ) where

import Aweb.Config (Config (..))
import Client qualified as Nats
import Control.Exception (SomeException, try)
import Data.Text (Text)
import Data.Text qualified as T
import JetStream qualified as JS
import JetStream.Types qualified as JS

-- | NATS environment holding the live connection and JetStream context.
data NatsEnv = NatsEnv
  { client    :: Nats.Client
  , jetStream :: JS.JetStreamContext
  }

-- | Connect to NATS and set up JetStream streams.
-- Returns Nothing if the connection fails (server unavailable).
connectNats :: Config -> IO (Maybe NatsEnv)
connectNats cfg = do
  let (host, port) = parseNatsUrl cfg.natsUrl
  result <- try (Nats.newClient [(host, port)]
    [ Nats.withConnectName "aweb-hs"
    , Nats.withConnectionAttempts 3
    ]) :: IO (Either SomeException Nats.Client)
  case result of
    Left e -> do
      putStrLn $ "NATS: connection failed: " <> show e
      pure Nothing
    Right nc -> do
      let jsCtx = JS.jetStream nc
      ensureStreams jsCtx
      putStrLn $ "NATS: connected to " <> host <> ":" <> show port
      pure $ Just NatsEnv { client = nc, jetStream = jsCtx }

-- | Disconnect from NATS server.
disconnectNats :: Maybe NatsEnv -> IO ()
disconnectNats Nothing    = pure ()
disconnectNats (Just env) = Nats.close env.client

-- | Parse "nats://host:port" into (host, port). Defaults to localhost:4222.
parseNatsUrl :: Text -> (String, Int)
parseNatsUrl url =
  let stripped = maybe url id
        $ T.stripPrefix "nats://" url
      (hostT, portT) = T.breakOn ":" stripped
      host = if T.null hostT then "localhost" else T.unpack hostT
      port = case T.stripPrefix ":" portT >>= readPort of
        Just p  -> p
        Nothing -> 4222
  in (host, port)
  where
    readPort t = case reads (T.unpack t) of
      [(p, "")] -> Just p
      _         -> Nothing

-- | Create JetStream streams if they don't already exist.
ensureStreams :: JS.JetStreamContext -> IO ()
ensureStreams ctx = do
  mapM_ ensureStream
    [ JS.StreamConfig
        { scName = "AWEB_MAIL"
        , scSubjects = ["aweb.mail.>"]
        , scRetention = JS.LimitsPolicy
        , scStorage = JS.FileStorage
        , scNumReplicas = 1
        , scMaxMsgs = Just 100000
        , scMaxBytes = Nothing
        , scMaxAge = Nothing
        , scMaxMsgSize = Nothing
        , scDiscard = Nothing
        , scDuplicates = Nothing
        }
    , JS.StreamConfig
        { scName = "AWEB_CHAT"
        , scSubjects = ["agents.prompt.aweb.>"]
        , scRetention = JS.LimitsPolicy
        , scStorage = JS.FileStorage
        , scNumReplicas = 1
        , scMaxMsgs = Just 100000
        , scMaxBytes = Nothing
        , scMaxAge = Nothing
        , scMaxMsgSize = Nothing
        , scDiscard = Nothing
        , scDuplicates = Nothing
        }
    , JS.StreamConfig
        { scName = "AWEB_EVENTS"
        , scSubjects = ["aweb.events.>"]
        , scRetention = JS.LimitsPolicy
        , scStorage = JS.FileStorage
        , scNumReplicas = 1
        , scMaxMsgs = Just 50000
        , scMaxBytes = Nothing
        , scMaxAge = Just (7 * 24 * 3600 * 1000000000) -- 7 days in nanoseconds
        , scMaxMsgSize = Nothing
        , scDiscard = Nothing
        , scDuplicates = Nothing
        }
    ]
  where
    ensureStream cfg = do
      result <- JS.createStream ctx cfg
      case result of
        Right _  -> putStrLn $ "NATS: stream " <> T.unpack (JS.scName cfg) <> " ready"
        Left (JS.JsApiError e)
          | JS.aeErrCode e == 10058 -> -- stream already exists
              putStrLn $ "NATS: stream " <> T.unpack (JS.scName cfg) <> " exists"
        Left e   -> putStrLn $ "NATS: stream " <> T.unpack (JS.scName cfg) <> " error: " <> show e
