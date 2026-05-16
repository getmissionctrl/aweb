module Aweb.DB
  ( Pool
  , withPool
  , runSession
  ) where

import Data.Text (Text)
import Hasql.Connection.Setting qualified as Connection.Setting
import Hasql.Connection.Setting.Connection qualified as Connection
import Hasql.Pool qualified as Pool
import Hasql.Pool.Config qualified as Pool.Config
import Hasql.Session (Session)

type Pool = Pool.Pool

-- | Create a connection pool from a database URL and run an action with it.
-- The pool is released when the action completes.
withPool :: Text -> (Pool -> IO a) -> IO a
withPool dbUrl action = do
  pool <- Pool.acquire poolConfig
  result <- action pool
  Pool.release pool
  pure result
  where
    poolConfig = Pool.Config.settings
      [ Pool.Config.size 10
      , Pool.Config.staticConnectionSettings
          [ Connection.Setting.connection (Connection.string dbUrl)
          ]
      ]

-- | Run a hasql session using a connection from the pool.
runSession :: Pool -> Session a -> IO (Either Pool.UsageError a)
runSession = Pool.use
