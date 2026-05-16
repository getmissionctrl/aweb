module Aweb.DB.TeamConfig
  ( listRoleVersions
  , getActiveRole
  , insertRoleVersion
  , listInstructionVersions
  , getActiveInstruction
  , insertInstructionVersion
  ) where

import Data.Text (Text)
import Rel8

import Aweb.DB.Schema
  ( TeamRole (..), teamRoleSchema
  , TeamInstruction (..), teamInstructionSchema
  )

-- | List all role versions for a team.
listRoleVersions :: Text -> Query (TeamRole Expr)
listRoleVersions teamId_ = do
  role <- each teamRoleSchema
  where_ $ role.teamId ==. lit teamId_
  pure role

-- | Get the currently active role for a team.
getActiveRole :: Text -> Query (TeamRole Expr)
getActiveRole teamId_ = do
  role <- each teamRoleSchema
  where_ $ role.teamId ==. lit teamId_
  where_ $ role.isActive ==. lit True
  pure role

-- | Insert a new role version.
insertRoleVersion :: TeamRole Expr -> Insert ()
insertRoleVersion role = Insert
  { into = teamRoleSchema
  , rows = values [role]
  , onConflict = Abort
  , returning = NoReturning
  }

-- | List all instruction versions for a team.
listInstructionVersions :: Text -> Query (TeamInstruction Expr)
listInstructionVersions teamId_ = do
  inst <- each teamInstructionSchema
  where_ $ inst.teamId ==. lit teamId_
  pure inst

-- | Get the currently active instruction for a team.
getActiveInstruction :: Text -> Query (TeamInstruction Expr)
getActiveInstruction teamId_ = do
  inst <- each teamInstructionSchema
  where_ $ inst.teamId ==. lit teamId_
  where_ $ inst.isActive ==. lit True
  pure inst

-- | Insert a new instruction version.
insertInstructionVersion :: TeamInstruction Expr -> Insert ()
insertInstructionVersion inst = Insert
  { into = teamInstructionSchema
  , rows = values [inst]
  , onConflict = Abort
  , returning = NoReturning
  }
