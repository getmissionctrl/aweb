module Aweb.DB.Agents
  ( listAgents
  , getAgentByAlias
  , getAgentByDID
  , insertAgent
  , softDeleteAgent
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Rel8

import Aweb.DB.Schema (Agent (..), agentSchema)

-- | List all non-deleted agents for a team.
listAgents :: Text -> Query (Agent Expr)
listAgents teamId_ = do
  agent <- each agentSchema
  where_ $ agent.teamId ==. lit teamId_
  where_ $ isNull agent.deletedAt
  pure agent

-- | Get a non-deleted agent by team and alias.
getAgentByAlias :: Text -> Text -> Query (Agent Expr)
getAgentByAlias teamId_ alias_ = do
  agent <- each agentSchema
  where_ $ agent.teamId ==. lit teamId_
  where_ $ agent.alias ==. lit alias_
  where_ $ isNull agent.deletedAt
  pure agent

-- | Get a non-deleted agent by DID key.
getAgentByDID :: Text -> Query (Agent Expr)
getAgentByDID did_ = do
  agent <- each agentSchema
  where_ $ agent.didKey ==. lit did_
  where_ $ isNull agent.deletedAt
  pure agent

-- | Insert a new agent row.
insertAgent :: Agent Expr -> Insert ()
insertAgent agent = Insert
  { into = agentSchema
  , rows = values [agent]
  , onConflict = Abort
  , returning = NoReturning
  }

-- | Soft-delete an agent by setting deletedAt.
softDeleteAgent :: UUID -> UTCTime -> Update ()
softDeleteAgent agentId_ ts = Update
  { target = agentSchema
  , from = pure ()
  , set = \_ agent -> agent { deletedAt = lit (Just ts) }
  , updateWhere = \_ agent -> agent.agentId ==. lit agentId_
  , returning = NoReturning
  }
