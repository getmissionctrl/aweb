module Aweb.Nats.Presence
  ( PresenceTracker
  , AgentPresence (..)
  , newPresenceTracker
  , getOnlineAgents
  , trackHeartbeat
  , expireStaleAgents
  ) where

import Control.Concurrent.STM (STM, TVar, atomically, newTVarIO, readTVar, modifyTVar')
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Time (UTCTime, getCurrentTime, diffUTCTime)

-- | Presence state for an agent
data AgentPresence = AgentPresence
  { alias         :: Text
  , teamId        :: Text
  , hostname      :: Maybe Text
  , workspacePath :: Maybe Text
  , focusTaskRef  :: Maybe Text
  , lastSeenAt    :: UTCTime
  }
  deriving stock (Show)

-- | Key for presence map: (team_id, alias)
type PresenceKey = (Text, Text)

-- | In-memory presence tracker backed by STM
newtype PresenceTracker = PresenceTracker
  { agents :: TVar (Map PresenceKey AgentPresence)
  }

-- | Create a new empty presence tracker
newPresenceTracker :: IO PresenceTracker
newPresenceTracker = PresenceTracker <$> newTVarIO Map.empty

-- | Get all online agents for a team (STM transaction)
getOnlineAgents :: PresenceTracker -> Text -> STM [AgentPresence]
getOnlineAgents tracker teamId = do
  m <- readTVar tracker.agents
  pure $ filter (\ap -> ap.teamId == teamId) (Map.elems m)

-- | Record a heartbeat for an agent
trackHeartbeat :: PresenceTracker -> Text -> Text -> Maybe Text -> Maybe Text -> Maybe Text -> IO ()
trackHeartbeat tracker teamId alias hostname wsPath focusTask = do
  now <- getCurrentTime
  let presence = AgentPresence
        { alias = alias
        , teamId = teamId
        , hostname = hostname
        , workspacePath = wsPath
        , focusTaskRef = focusTask
        , lastSeenAt = now
        }
  atomically $ modifyTVar' tracker.agents (Map.insert (teamId, alias) presence)

-- | Remove agents not seen in the last 30 seconds
expireStaleAgents :: PresenceTracker -> IO ()
expireStaleAgents tracker = do
  now <- getCurrentTime
  atomically $ modifyTVar' tracker.agents (Map.filter (isRecent now))
  where
    isRecent now ap = diffUTCTime now ap.lastSeenAt < 30
