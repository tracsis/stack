{-# LANGUAGE CPP            #-}
{-# LANGUAGE PackageImports #-}

module StackSetupShim where

-- | Stack no longer supports Cabal < 1.24 and, consequently, GHC versions
-- before GHC 8.0 or base < 4.9.0.0. Consequently, we do not need to test for
-- the existence of the MIN_VERSION_Cabal macro (provided from GHC 8.0).

import Data.List ( stripPrefix )
import Distribution.ReadE ( ReadE (..) )
import Distribution.Simple.Configure ( getPersistBuildConfig )
-- | Temporary, can be removed if initialBuildSteps restored to Cabal's API.
#if MIN_VERSION_Cabal(3,11,0)
import Distribution.Simple.Build ( writeBuiltinAutogenFiles )
#else
import Distribution.Simple.Build ( initialBuildSteps )
#endif
#if MIN_VERSION_Cabal(3,11,0)
import Distribution.Simple.Errors ( exceptionMessage )
#endif
-- | Temporary, can be removed if initialBuildSteps restored to Cabal's API.
#if MIN_VERSION_Cabal(3,11,0)
import Distribution.Simple.LocalBuildInfo
         ( componentBuildDir, withAllComponentsInBuildOrder )
#endif
#if MIN_VERSION_Cabal(3,8,1)
import Distribution.Simple.PackageDescription ( readGenericPackageDescription )
#elif MIN_VERSION_Cabal(2,2,0)
-- Avoid confusion with Cabal-syntax module of same name.
-- readGenericPackageDescription was exported from module
-- Distribution.PackageDescription.Parsec in Cabal-2.2.0.0.
import "Cabal" Distribution.PackageDescription.Parsec
         ( readGenericPackageDescription )
#elif MIN_VERSION_Cabal(2,0,0)
-- readPackageDescription was renamed readGenericPackageDescription in
-- Cabal-2.0.0.2.
import Distribution.PackageDescription.Parse ( readGenericPackageDescription )
#else
import Distribution.PackageDescription.Parse ( readPackageDescription )
#endif
import Distribution.Simple.Utils
         ( createDirectoryIfMissingVerbose, findPackageDesc )
#if MIN_VERSION_Cabal(3,8,1)
import Distribution.Types.GenericPackageDescription
         ( GenericPackageDescription (..) )
#elif MIN_VERSION_Cabal(2,0,0)
-- Avoid confusion with Cabal-syntax module of same name.
-- GenericPackageDescription was exported from module
-- Distribution.Types.GenericPackageDescription in Cabal-2.0.0.2.
import "Cabal" Distribution.Types.GenericPackageDescription
         ( GenericPackageDescription (..) )
#else
import Distribution.PackageDescription ( GenericPackageDescription (..) )
#endif
-- | Temporary, can be removed if initialBuildSteps restored to Cabal's API.
#if MIN_VERSION_Cabal(3,11,0)
import Distribution.Types.ComponentLocalBuildInfo ( ComponentLocalBuildInfo )
import Distribution.Types.LocalBuildInfo ( LocalBuildInfo )
import Distribution.Types.PackageDescription ( PackageDescription )
import Distribution.Verbosity ( Verbosity )
#endif
import Distribution.Verbosity ( flagToVerbosity )
import Main
-- Before base-4.11.0.0 (GHC 8.4.1), <> was not exported by Prelude.
#if !MIN_VERSION_base(4,11,0)
import Data.Semigroup ( (<>) )
#endif
import System.Environment ( getArgs )

mainOverride :: IO ()
mainOverride = do
  args <- getArgs
  case args of
    [arg1, arg2, "repl", "stack-initial-build-steps"] -> stackReplHook arg1 arg2
    _ -> main

-- | The name of the function is a mismomer, but is kept for historical reasons.
-- This function relies on Stack calling the 'setup' executable with:
--
-- --verbose=<Cabal_verbosity>
-- --builddir=<path_to_dist_prefix>
-- repl
-- stack-initial-build-steps
stackReplHook :: String -> String -> IO ()
stackReplHook arg1 arg2 = do
  let mRawVerbosity = stripPrefix "--verbose=" arg1
      mRawBuildDir = stripPrefix "--builddir=" arg2
  case (mRawVerbosity, mRawBuildDir) of
    (Nothing, _) -> fail $
      "Misuse of running Setup.hs with stack-initial-build-steps, expected " <>
      "first argument to start --verbose="
    (_, Nothing) -> fail $
      "Misuse of running Setup.hs with stack-initial-build-steps, expected" <>
      "second argument to start --builddir="
    (Just rawVerbosity, Just rawBuildDir) -> do
        let eVerbosity = runReadE flagToVerbosity rawVerbosity
        case eVerbosity of
          Left msg1 -> fail $
            "Unexpected happened running Setup.hs with " <>
            "stack-initial-build-steps, expected to parse Cabal verbosity: " <>
            msg1
          Right verbosity -> do
            eFp <- findPackageDesc ""
            case eFp of
              Left err -> fail $
                "Unexpected happened running Setup.hs with " <>
                "stack-initial-build-steps, expected to find a Cabal file: " <>
                msg2
               where
#if MIN_VERSION_Cabal(3,11,0)
                -- The type of findPackageDesc changed in Cabal-3.11.0.0.
                msg2 = exceptionMessage err
#else
                msg2 = err
#endif
              Right fp -> do
                gpd <-
#if MIN_VERSION_Cabal(2,0,0)
                  readGenericPackageDescription verbosity fp
#else
                  readPackageDescription verbosity fp
#endif
                let pd = packageDescription gpd
                lbi <- getPersistBuildConfig rawBuildDir
                initialBuildSteps rawBuildDir pd lbi verbosity

-- | Temporary, can be removed if initialBuildSteps restored to Cabal's API.
-- Based on the functions of the same name provided by Cabal-3.10.3.0.
#if MIN_VERSION_Cabal(3,11,0)
-- | Runs 'componentInitialBuildSteps' on every configured component.
initialBuildSteps ::
     FilePath -- ^"dist" prefix
  -> PackageDescription  -- ^mostly information from the .cabal file
  -> LocalBuildInfo -- ^Configuration information
  -> Verbosity -- ^The verbosity to use
  -> IO ()
initialBuildSteps distPref pkg_descr lbi verbosity =
  withAllComponentsInBuildOrder pkg_descr lbi $ \_comp clbi ->
    componentInitialBuildSteps distPref pkg_descr lbi clbi verbosity

-- | Creates the autogenerated files for a particular configured component.
componentInitialBuildSteps ::
     FilePath -- ^"dist" prefix
  -> PackageDescription  -- ^mostly information from the .cabal file
  -> LocalBuildInfo -- ^Configuration information
  -> ComponentLocalBuildInfo
  -> Verbosity -- ^The verbosity to use
  -> IO ()
componentInitialBuildSteps _distPref pkg_descr lbi clbi verbosity = do
  createDirectoryIfMissingVerbose verbosity True (componentBuildDir lbi clbi)
  -- Cabal-3.10.3.0 used writeAutogenFiles, that generated and wrote out the
  -- Paths_<pkg>.hs, PackageInfo_<pkg>.hs, and cabal_macros.h files. This
  -- appears to be the equivalent function for Cabal-3.11.0.0.
  writeBuiltinAutogenFiles verbosity pkg_descr lbi clbi
#endif
