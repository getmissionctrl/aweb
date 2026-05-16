module Aweb.Config
  ( Config (..)
  , parseConfig
  ) where

import Data.Text (Text)
import Options.Applicative

data Config = Config
  { httpPort    :: !Int
  , databaseUrl :: !Text
  , natsUrl     :: !Text
  , awidUrl     :: !Text
  , logLevel    :: !Text
  }
  deriving stock (Show)

parseConfig :: IO Config
parseConfig = execParser opts
  where
    opts = info (configParser <**> helper)
      (fullDesc <> progDesc "aweb coordination server (Haskell)")

configParser :: Parser Config
configParser = Config
  <$> option auto
      (long "port" <> short 'p' <> value 8080 <> help "HTTP port")
  <*> strOption
      (long "database-url" <> value "postgresql://aweb:aweb@localhost:5433/aweb" <> help "PostgreSQL URL")
  <*> strOption
      (long "nats-url" <> value "nats://localhost:4222" <> help "NATS server URL")
  <*> strOption
      (long "awid-url" <> value "http://localhost:8010" <> help "awid registry URL")
  <*> strOption
      (long "log-level" <> value "info" <> help "Log level")
