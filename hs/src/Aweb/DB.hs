module Aweb.DB
  ( Pool
  , withPool
  , runDB
  , runSelect
  , runInsert
  , runUpdate
  , runDelete
  , throwDB
  , runMigrations
  ) where

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text, pack)
import Data.Text.Encoding qualified as TE
import Hasql.Connection.Setting qualified as Connection.Setting
import Hasql.Connection.Setting.Connection qualified as Connection
import Hasql.Pool qualified as Pool
import Hasql.Pool.Config qualified as Pool.Config
import Hasql.Session (Session)
import Hasql.Session qualified as Session
import Hasql.Statement qualified as Statement
import Rel8 (Delete, Insert, Query, Serializable, Table, Expr, Update)
import Rel8 qualified
import Servant (Handler, ServerError (..), err500, throwError)

type Pool = Pool.Pool

-- | Create a connection pool from a database URL and run an action with it.
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

-- | Run a hasql Session using the pool. Left = DB error.
runDB :: Pool -> Session a -> IO (Either Pool.UsageError a)
runDB = Pool.use

-- | Run a rel8 SELECT query.
runSelect :: (Table Expr exprs, Serializable exprs a) => Pool -> Query exprs -> IO (Either Pool.UsageError [a])
runSelect pool q = Pool.use pool (Session.statement () (Rel8.run (Rel8.select q)))

-- | Run a rel8 INSERT (no returning).
runInsert :: Pool -> Insert () -> IO (Either Pool.UsageError ())
runInsert pool ins = Pool.use pool (Session.statement () (Rel8.run_ (Rel8.insert ins)))

-- | Run a rel8 UPDATE (no returning).
runUpdate :: Pool -> Update () -> IO (Either Pool.UsageError ())
runUpdate pool upd = Pool.use pool (Session.statement () (Rel8.run_ (Rel8.update upd)))

-- | Run a rel8 DELETE (no returning).
runDelete :: Pool -> Delete () -> IO (Either Pool.UsageError ())
runDelete pool del = Pool.use pool (Session.statement () (Rel8.run_ (Rel8.delete del)))

-- | Convert a DB error to a Servant 500 error in Handler.
throwDB :: Pool.UsageError -> Handler a
throwDB err = throwError err500
  { errBody = LBS.fromStrict (TE.encodeUtf8 (pack ("Database error: " <> show err)))
  }

-- | Run migration SQL files against the pool on startup.
runMigrations :: Pool -> [FilePath] -> IO ()
runMigrations pool paths = do
  mapM_ runOne paths
  where
    runOne path = do
      sql <- BS.readFile path
      result <- Pool.use pool (Session.sql sql)
      case result of
        Right () -> putStrLn $ "Migration applied: " <> path
        Left e   -> putStrLn $ "Migration failed (" <> path <> "): " <> show e
