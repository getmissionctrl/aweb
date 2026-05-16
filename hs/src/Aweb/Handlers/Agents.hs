module Aweb.Handlers.Agents
  ( agentsServer
  ) where

import Aweb.API (AgentsAPI)
import Servant

-- | Agents endpoint handlers (stub implementation)
agentsServer :: Server AgentsAPI
agentsServer =
       registerAgent
  :<|> listAgents
  :<|> getAgent
  :<|> deleteAgent
  :<|> suggestAliasPrefix
  where
    registerAgent _req = throwError err501
    listAgents = throwError err501
    getAgent _alias = throwError err501
    deleteAgent _alias = throwError err501
    suggestAliasPrefix = throwError err501
