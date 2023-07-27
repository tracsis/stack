
{-# LANGUAGE NoImplicitPrelude #-}

module Stack.Types.StackYamlLoc
  ( StackYamlLoc (..)
  ) where

import           Stack.Prelude

-- | Location for the project's stack.yaml file.
data StackYamlLoc
  = SYLDefault
    -- ^ Use the standard parent-directory-checking logic
  | SYLOverride !(Path Abs File)
    -- ^ Use a specific stack.yaml file provided
  | SYLNoProject ![PackageIdentifierRevision]
    -- ^ Do not load up a project, just user configuration. Include
    -- the given extra dependencies with the resolver.
  | SYLGlobalProject
    -- ^ Do not look for a project configuration, and use the implicit global.
  deriving Show
