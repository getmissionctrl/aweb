module Aweb.Handlers.Instructions
  ( instructionsServer
  ) where

import Aweb.API (InstructionsAPI)
import Servant

-- | Instructions endpoint handlers (stub implementation)
instructionsServer :: Server InstructionsAPI
instructionsServer =
       createInstructionVersion
  :<|> listInstructionVersions
  :<|> getActiveInstruction
  :<|> activateInstruction
  where
    createInstructionVersion _req = throwError err501
    listInstructionVersions = throwError err501
    getActiveInstruction = throwError err501
    activateInstruction _version = throwError err501
