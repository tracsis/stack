{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NoFieldSelectors      #-}
{-# LANGUAGE OverloadedRecordDot   #-}
{-# LANGUAGE OverloadedStrings     #-}

-- | Types and functions related to Stack's @setup@ command.
module Stack.SetupCmd
  ( SetupCmdOpts (..)
  , setupCmd
  , setup
  ) where

import           Stack.Prelude
import           Stack.Runners
                   ( ShouldReexec (..), withBuildConfig, withConfig )
import           Stack.Setup ( SetupOpts (..), ensureCompilerAndMsys )
import           Stack.Types.BuildConfig
                   ( HasBuildConfig, stackYamlL, wantedCompilerVersionL )
import           Stack.Types.CompilerPaths ( CompilerPaths (..) )
import           Stack.Types.Config ( Config (..), HasConfig (..) )
import           Stack.Types.GHCVariant ( HasGHCVariant )
import           Stack.Types.Runner ( Runner )
import           Stack.Types.Version ( VersionCheck (..) )

-- | Type representing command line options for the @stack setup@ command.
data SetupCmdOpts = SetupCmdOpts
  { compilerVersion :: !(Maybe WantedCompiler)
  , forceReinstall  :: !Bool
  , ghcBindistUrl   :: !(Maybe String)
  , ghcjsBootOpts   :: ![String]
  , ghcjsBootClean  :: !Bool
  }

-- | Function underlying the @stack setup@ command.
setupCmd :: SetupCmdOpts -> RIO Runner ()
setupCmd sco = withConfig YesReexec $ do
  installGHC <- view $ configL . to (.installGHC)
  if installGHC
    then
       withBuildConfig $ do
       (wantedCompiler, compilerCheck, mstack) <-
         case sco.compilerVersion of
           Just v -> pure (v, MatchMinor, Nothing)
           Nothing -> (,,)
             <$> view wantedCompilerVersionL
             <*> view (configL . to (.compilerCheck))
             <*> (Just <$> view stackYamlL)
       setup sco wantedCompiler compilerCheck mstack
    else
      prettyWarnL
        [ "The"
        , style Shell "--no-install-ghc"
        , flow "flag is inconsistent with"
        , style Shell (flow "stack setup") <> "."
        , flow "No action taken."
        ]

setup ::
     (HasBuildConfig env, HasGHCVariant env)
  => SetupCmdOpts
  -> WantedCompiler
  -> VersionCheck
  -> Maybe (Path Abs File)
  -> RIO env ()
setup sco wantedCompiler compilerCheck stackYaml = do
  config <- view configL
  sandboxedGhc <- (.sandboxed) . fst <$> ensureCompilerAndMsys SetupOpts
    { installIfMissing = True
    , useSystem = config.systemGHC && not sco.forceReinstall
    , wantedCompiler
    , compilerCheck
    , stackYaml
    , forceReinstall = sco.forceReinstall
    , sanityCheck = True
    , skipGhcCheck = False
    , skipMsys = config.skipMsys
    , resolveMissingGHC = Nothing
    , ghcBindistURL = sco.ghcBindistUrl
    }
  let compiler = case wantedCompiler of
        WCGhc _ -> "GHC"
        WCGhcGit{} -> "GHC (built from source)"
        WCGhcjs {} -> "GHCJS"
      compilerHelpMsg = fillSep
        [ flow "To use this"
        , compiler
        , flow "and packages outside of a project, consider using:"
        , style Shell (flow "stack ghc") <> ","
        , style Shell (flow "stack ghci") <> ","
        , style Shell (flow "stack runghc") <> ","
        , "or"
        , style Shell (flow "stack exec") <> "."
        ]
  if sandboxedGhc
    then prettyInfoL
      [ flow "Stack will use a sandboxed"
      , compiler
      , flow "it installed."
      , compilerHelpMsg
      ]
    else prettyInfoL
      [ flow "Stack will use the"
      , compiler
      , flow "on your PATH. For more information on paths, see"
      , style Shell (flow "stack path")
      , "and"
      , style Shell (flow "stack exec env") <> "."
      , compilerHelpMsg
      ]
