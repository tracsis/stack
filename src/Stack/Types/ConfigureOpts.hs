{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}

module Stack.Types.ConfigureOpts
  ( ConfigureOpts (..)
  , BaseConfigOpts (..)
  , configureOpts
  , configureOptsDirs
  , configureOptsNoDir
  ) where

import qualified Data.Map as Map
import qualified Data.Text as T
import           Distribution.Types.MungedPackageName
                   ( decodeCompatPackageName )
import           Distribution.Types.PackageName ( unPackageName )
import           Distribution.Types.UnqualComponentName
                   ( unUnqualComponentName )
import qualified Distribution.Version as C
import           Path ( (</>), parseRelDir )
import           Path.Extra ( toFilePathNoTrailingSep )
import           Stack.Constants
                   ( bindirSuffix, compilerOptionsCabalFlag, docDirSuffix
                   , relDirEtc, relDirLib, relDirLibexec, relDirShare
                   )
import           Stack.Prelude
import           Stack.Types.BuildOpts ( BuildOpts (..), BuildOptsCLI )
import           Stack.Types.Compiler ( getGhcVersion, whichCompiler )
import           Stack.Types.Config
                   ( Config (..), HasConfig (..) )
import           Stack.Types.EnvConfig ( EnvConfig, actualCompilerVersionL )
import           Stack.Types.GhcPkgId ( GhcPkgId, ghcPkgIdString )
import           Stack.Types.IsMutable ( IsMutable (..) )
import           Stack.Types.Package ( Package (..) )
import           System.FilePath ( pathSeparator )

-- | Basic information used to calculate what the configure options are
data BaseConfigOpts = BaseConfigOpts
  { bcoSnapDB :: !(Path Abs Dir)
  , bcoLocalDB :: !(Path Abs Dir)
  , bcoSnapInstallRoot :: !(Path Abs Dir)
  , bcoLocalInstallRoot :: !(Path Abs Dir)
  , bcoBuildOpts :: !BuildOpts
  , bcoBuildOptsCLI :: !BuildOptsCLI
  , bcoExtraDBs :: ![Path Abs Dir]
  }
  deriving Show

-- | Render a @BaseConfigOpts@ to an actual list of options
configureOpts :: EnvConfig
              -> BaseConfigOpts
              -> Map PackageIdentifier GhcPkgId -- ^ dependencies
              -> Bool -- ^ local non-extra-dep?
              -> IsMutable
              -> Package
              -> ConfigureOpts
configureOpts econfig bco deps isLocal isMutable package = ConfigureOpts
  { coDirs = configureOptsDirs bco isMutable package
  , coNoDirs = configureOptsNoDir econfig bco deps isLocal package
  }


configureOptsDirs :: BaseConfigOpts
                  -> IsMutable
                  -> Package
                  -> [String]
configureOptsDirs bco isMutable package = concat
  [ ["--user", "--package-db=clear", "--package-db=global"]
  , map (("--package-db=" ++) . toFilePathNoTrailingSep) $ case isMutable of
      Immutable -> bcoExtraDBs bco ++ [bcoSnapDB bco]
      Mutable -> bcoExtraDBs bco ++ [bcoSnapDB bco] ++ [bcoLocalDB bco]
  , [ "--libdir=" ++ toFilePathNoTrailingSep (installRoot </> relDirLib)
    , "--bindir=" ++ toFilePathNoTrailingSep (installRoot </> bindirSuffix)
    , "--datadir=" ++ toFilePathNoTrailingSep (installRoot </> relDirShare)
    , "--libexecdir=" ++ toFilePathNoTrailingSep (installRoot </> relDirLibexec)
    , "--sysconfdir=" ++ toFilePathNoTrailingSep (installRoot </> relDirEtc)
    , "--docdir=" ++ toFilePathNoTrailingSep docDir
    , "--htmldir=" ++ toFilePathNoTrailingSep docDir
    , "--haddockdir=" ++ toFilePathNoTrailingSep docDir]
  ]
 where
  installRoot =
    case isMutable of
      Immutable -> bcoSnapInstallRoot bco
      Mutable -> bcoLocalInstallRoot bco
  docDir =
    case pkgVerDir of
      Nothing -> installRoot </> docDirSuffix
      Just dir -> installRoot </> docDirSuffix </> dir
  pkgVerDir = parseRelDir
    (  packageIdentifierString
        (PackageIdentifier (packageName package) (packageVersion package))
    ++ [pathSeparator]
    )

-- | Same as 'configureOpts', but does not include directory path options
configureOptsNoDir ::
     EnvConfig
  -> BaseConfigOpts
  -> Map PackageIdentifier GhcPkgId -- ^ Dependencies.
  -> Bool -- ^ Is this a local, non-extra-dep?
  -> Package
  -> [String]
configureOptsNoDir econfig bco deps isLocal package = concat
  [ depOptions
  , [ "--enable-library-profiling"
    | boptsLibProfile bopts || boptsExeProfile bopts
    ]
  , ["--enable-profiling" | boptsExeProfile bopts && isLocal]
  , ["--enable-split-objs" | boptsSplitObjs bopts]
  , [ "--disable-library-stripping"
    | not $ boptsLibStrip bopts || boptsExeStrip bopts
    ]
  , ["--disable-executable-stripping" | not (boptsExeStrip bopts) && isLocal]
  , map (\(name,enabled) ->
                     "-f" <>
                     (if enabled
                        then ""
                        else "-") <>
                     flagNameString name)
                  (Map.toList flags)
  , map T.unpack $ packageCabalConfigOpts package
  , processGhcOptions (packageGhcOptions package)
  , map ("--extra-include-dirs=" ++) (configExtraIncludeDirs config)
  , map ("--extra-lib-dirs=" ++) (configExtraLibDirs config)
  , maybe
      []
      (\customGcc -> ["--with-gcc=" ++ toFilePath customGcc])
      (configOverrideGccPath config)
  , ["--exact-configuration"]
  , ["--ghc-option=-fhide-source-paths" | hideSourcePaths cv]
  ]
 where
  -- This function parses the GHC options that are providing in the
  -- stack.yaml file. In order to handle RTS arguments correctly, we need
  -- to provide the RTS arguments as a single argument.
  processGhcOptions :: [Text] -> [String]
  processGhcOptions args =
    let (preRtsArgs, mid) = break ("+RTS" ==) args
        (rtsArgs, end) = break ("-RTS" ==) mid
        fullRtsArgs =
          case rtsArgs of
            [] ->
              -- This means that we didn't have any RTS args - no `+RTS` - and
              -- therefore no need for a `-RTS`.
              []
            _ ->
              -- In this case, we have some RTS args. `break` puts the `"-RTS"`
              -- string in the `snd` list, so we want to append it on the end of
              -- `rtsArgs` here.
              --
              -- We're not checking that `-RTS` is the first element of `end`.
              -- This is because the GHC RTS allows you to omit a trailing -RTS
              -- if that's the last of the arguments. This permits a GHC options
              -- in stack.yaml that matches what you might pass directly to GHC.
              [T.unwords $ rtsArgs ++ ["-RTS"]]
        -- We drop the first element from `end`, because it is always either
        -- `"-RTS"` (and we don't want that as a separate argument) or the list
        -- is empty (and `drop _ [] = []`).
        postRtsArgs = drop 1 end
        newArgs = concat [preRtsArgs, fullRtsArgs, postRtsArgs]
    in  concatMap (\x -> [compilerOptionsCabalFlag wc, T.unpack x]) newArgs

  wc = view (actualCompilerVersionL.to whichCompiler) econfig
  cv = view (actualCompilerVersionL.to getGhcVersion) econfig

  hideSourcePaths ghcVersion =
    ghcVersion >= C.mkVersion [8, 2] && configHideSourcePaths config

  config = view configL econfig
  bopts = bcoBuildOpts bco

  -- Unioning atop defaults is needed so that all flags are specified with
  -- --exact-configuration.
  flags = packageFlags package `Map.union` packageDefaultFlags package

  depOptions = map toDepOption $ Map.toList deps

  toDepOption (PackageIdentifier name _, gid) = concat
    [ "--dependency="
    , depOptionKey
    , "="
    , ghcPkgIdString gid
    ]
   where
    MungedPackageName subPkgName lib = decodeCompatPackageName name
    depOptionKey = case lib of
      LMainLibName -> unPackageName name
      LSubLibName cn ->
        unPackageName subPkgName <> ":" <> unUnqualComponentName cn

-- | Configure options to be sent to Setup.hs configure
data ConfigureOpts = ConfigureOpts
  { coDirs :: ![String]
    -- ^ Options related to various paths. We separate these out since they do
    -- not have an impact on the contents of the compiled binary for checking
    -- if we can use an existing precompiled cache.
  , coNoDirs :: ![String]
  }
  deriving (Data, Eq, Generic, Show, Typeable)

instance NFData ConfigureOpts
