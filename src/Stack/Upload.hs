{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedStrings   #-}

-- | Types and functions related to Stack's @upload@ command.
module Stack.Upload
  ( -- * Upload
    UploadOpts (..)
  , UploadVariant (..)
  , uploadCmd
  , upload
  , uploadBytes
  , uploadRevision
    -- * Credentials
  , HackageCreds
  , HackageAuth (..)
  , HackageKey (..)
  , loadAuth
  , writeFilePrivate
    -- * Internal
  , maybeGetHackageKey
  ) where

import           Conduit ( mapOutput, sinkList )
import           Data.Aeson
                   ( FromJSON (..), ToJSON (..), (.:), (.=), decode'
                   , fromEncoding, object, toEncoding, withObject
                   )
import           Data.ByteString.Builder ( lazyByteString )
import qualified Data.ByteString.Char8 as S
import qualified Data.ByteString.Lazy as L
import qualified Data.Conduit.Binary as CB
import qualified Data.Text as T
import           Network.HTTP.StackClient
                   ( Request, RequestBody (RequestBodyLBS), Response
                   , applyDigestAuth, displayDigestAuthException, formDataBody
                   , getGlobalManager, getResponseBody, getResponseStatusCode
                   , httpNoBody, parseRequest, partBS, partFileRequestBody
                   , partLBS, setRequestHeader, withResponse
                   )
import           Path.IO ( resolveDir', resolveFile' )
import           Stack.Prelude
import           Stack.Runners
                   ( ShouldReexec (..), withConfig, withDefaultEnvConfig )
import           Stack.SDist
                   ( SDistOpts (..), checkSDistTarball, checkSDistTarball'
                   , getSDistTarball
                   )
import           Stack.Types.Config ( Config (..), configL, stackRootL )
import           Stack.Types.Runner ( Runner )
import           System.Directory
                   ( createDirectoryIfMissing, doesDirectoryExist, doesFileExist
                   , removeFile, renameFile
                   )
import           System.Environment ( lookupEnv )
import           System.FilePath ( (</>), takeDirectory, takeFileName )
import           System.PosixCompat.Files ( setFileMode )

-- | Type representing \'pretty\' exceptions thrown by functions exported by the
-- "Stack.Upload" module.
data UploadPrettyException
  = AuthenticationFailure
  | ArchiveUploadFailure Int [String] String
  deriving (Show, Typeable)

instance Pretty UploadPrettyException where
  pretty AuthenticationFailure =
       "[S-2256]"
    <> line
    <> flow "authentification failure"
    <> line
    <> flow "Authentication failure uploading to server"
  pretty (ArchiveUploadFailure code res tarName) =
       "[S-6108]"
    <> line
    <> flow "unhandled status code:" <+> fromString (show code)
    <> line
    <> flow "Upload failed on" <+> style File (fromString tarName)
    <> line
    <> vsep (map string res)

instance Exception UploadPrettyException

-- Type representing variants for uploading to Hackage.
data UploadVariant
  = Publishing
  -- ^ Publish the package
  | Candidate
  -- ^ Create a package candidate

-- | Type representing command line options for the @stack upload@ command.
data UploadOpts = UploadOpts
  { uoptsSDistOpts :: SDistOpts
  , uoptsUploadVariant :: UploadVariant
  -- ^ Says whether to publish the package or upload as a release candidate
  }

-- | Function underlying the @stack upload@ command. Upload to Hackage.
uploadCmd :: UploadOpts -> RIO Runner ()
uploadCmd (UploadOpts (SDistOpts [] _ _ _ _) _) = do
  prettyErrorL
    [ flow "To upload the current package, please run"
    , style Shell "stack upload ."
    , flow "(with the period at the end)"
    ]
  liftIO exitFailure
uploadCmd uploadOpts = do
  let partitionM _ [] = pure ([], [])
      partitionM f (x:xs) = do
        r <- f x
        (as, bs) <- partitionM f xs
        pure $ if r then (x:as, bs) else (as, x:bs)
      sdistOpts = uoptsSDistOpts uploadOpts
  (files, nonFiles) <-
    liftIO $ partitionM doesFileExist (sdoptsDirsToWorkWith sdistOpts)
  (dirs, invalid) <- liftIO $ partitionM doesDirectoryExist nonFiles
  withConfig YesReexec $ withDefaultEnvConfig $ do
    unless (null invalid) $ do
      let invalidList = bulletedList $ map (style File . fromString) invalid
      prettyErrorL
        [ style Shell "stack upload"
        , flow "expects a list of sdist tarballs or package directories."
        , flow "Can't find:"
        , line <> invalidList
        ]
      exitFailure
    when (null files && null dirs) $ do
      prettyErrorL
        [ style Shell "stack upload"
        , flow "expects a list of sdist tarballs or package directories, but none were specified."
        ]
      exitFailure
    config <- view configL
    let hackageUrl = T.unpack $ configHackageBaseUrl config
        uploadVariant = uoptsUploadVariant uploadOpts
    getCreds <- memoizeRef $ loadAuth config
    mapM_ (resolveFile' >=> checkSDistTarball sdistOpts) files
    forM_ files $ \file -> do
      tarFile <- resolveFile' file
      creds <- runMemoized getCreds
      upload hackageUrl creds (toFilePath tarFile) uploadVariant
    forM_ dirs $ \dir -> do
      pkgDir <- resolveDir' dir
      (tarName, tarBytes, mcabalRevision) <-
        getSDistTarball (sdoptsPvpBounds sdistOpts) pkgDir
      checkSDistTarball' sdistOpts tarName tarBytes
      creds <- runMemoized getCreds
      uploadBytes hackageUrl creds tarName uploadVariant tarBytes
      forM_ mcabalRevision $ uncurry $ uploadRevision hackageUrl creds

newtype HackageKey = HackageKey Text
  deriving (Eq, Show)

-- | Username and password to log into Hackage.
--
-- Since 0.1.0.0
data HackageCreds = HackageCreds
  { hcUsername :: !Text
  , hcPassword :: !Text
  , hcCredsFile :: !FilePath
  }
  deriving (Eq, Show)

data HackageAuth
  = HAKey HackageKey
  | HACreds HackageCreds
  deriving (Eq, Show)

instance ToJSON HackageCreds where
  toJSON (HackageCreds u p _) = object
    [ "username" .= u
    , "password" .= p
    ]

instance FromJSON (FilePath -> HackageCreds) where
  parseJSON = withObject "HackageCreds" $ \o -> HackageCreds
    <$> o .: "username"
    <*> o .: "password"

withEnvVariable :: Text -> IO Text -> IO Text
withEnvVariable varName fromPrompt =
  lookupEnv (T.unpack varName) >>= maybe fromPrompt (pure . T.pack)

maybeGetHackageKey :: RIO m (Maybe HackageKey)
maybeGetHackageKey =
  liftIO $ fmap (HackageKey . T.pack) <$> lookupEnv "HACKAGE_KEY"

loadAuth :: (HasLogFunc m, HasTerm m) => Config -> RIO m HackageAuth
loadAuth config = do
  maybeHackageKey <- maybeGetHackageKey
  case maybeHackageKey of
    Just key -> do
      prettyInfoS
        "HACKAGE_KEY environment variable found, using that for credentials."
      pure $ HAKey key
    Nothing -> HACreds <$> loadUserAndPassword config

-- | Load Hackage credentials, either from a save file or the command
-- line.
--
-- Since 0.1.0.0
loadUserAndPassword :: HasTerm m => Config -> RIO m HackageCreds
loadUserAndPassword config = do
  fp <- liftIO $ credsFile config
  elbs <- liftIO $ tryIO $ L.readFile fp
  case either (const Nothing) Just elbs >>= \lbs -> (lbs, ) <$> decode' lbs of
    Nothing -> fromPrompt fp
    Just (lbs, mkCreds) -> do
      -- Ensure privacy, for cleaning up old versions of Stack that
      -- didn't do this
      writeFilePrivate fp $ lazyByteString lbs

      unless (configSaveHackageCreds config) $ do
        prettyWarnL
          [ flow "You've set save-hackage-creds to false. However, credentials \
                 \ were found at:"
          , style File (fromString fp) <> "."
          ]
      pure $ mkCreds fp
 where
  fromPrompt :: HasTerm m => FilePath -> RIO m HackageCreds
  fromPrompt fp = do
    username <- liftIO $ withEnvVariable "HACKAGE_USERNAME" (prompt "Hackage username: ")
    password <- liftIO $ withEnvVariable "HACKAGE_PASSWORD" (promptPassword "Hackage password: ")
    let hc = HackageCreds
          { hcUsername = username
          , hcPassword = password
          , hcCredsFile = fp
          }

    when (configSaveHackageCreds config) $ do
      shouldSave <- promptBool $ T.pack $
        "Save Hackage credentials to file at " ++ fp ++ " [y/n]? "
      prettyNoteL
        [ flow "Avoid this prompt in the future by using the configuration \
               \file option"
        , style Shell (flow "save-hackage-creds: false") <> "."
        ]
      when shouldSave $ do
        writeFilePrivate fp $ fromEncoding $ toEncoding hc
        prettyInfoS "Saved!"
        hFlush stdout

    pure hc

-- | Write contents to a file which is always private.
--
-- For history of this function, see:
--
-- * https://github.com/commercialhaskell/stack/issues/2159#issuecomment-477948928
--
-- * https://github.com/commercialhaskell/stack/pull/4665
writeFilePrivate :: MonadIO m => FilePath -> Builder -> m ()
writeFilePrivate fp builder =
  liftIO $ withTempFile (takeDirectory fp) (takeFileName fp) $ \fpTmp h -> do
    -- Temp file is created such that only current user can read and write it.
    -- See docs for openTempFile:
    -- https://www.stackage.org/haddock/lts-13.14/base-4.12.0.0/System-IO.html#v:openTempFile

    -- Write to the file and close the handle.
    hPutBuilder h builder
    hClose h

    -- Make sure the destination file, if present, is writeable
    void $ tryIO $ setFileMode fp 0o600

    -- And atomically move
    renameFile fpTmp fp

credsFile :: Config -> IO FilePath
credsFile config = do
  let dir = toFilePath (view stackRootL config) </> "upload"
  createDirectoryIfMissing True dir
  pure $ dir </> "credentials.json"

addAPIKey :: HackageKey -> Request -> Request
addAPIKey (HackageKey key) = setRequestHeader
  "Authorization"
  [fromString $ "X-ApiKey" ++ " " ++ T.unpack key]

applyAuth ::
     (HasLogFunc m, HasTerm m)
  => HackageAuth
  -> Request
  -> RIO m Request
applyAuth haAuth req0 =
  case haAuth of
    HAKey key -> pure (addAPIKey key req0)
    HACreds creds -> applyCreds creds req0

applyCreds ::
     (HasLogFunc m, HasTerm m)
  => HackageCreds
  -> Request
  -> RIO m Request
applyCreds creds req0 = do
  manager <- liftIO getGlobalManager
  ereq <- liftIO $ applyDigestAuth
    (encodeUtf8 $ hcUsername creds)
    (encodeUtf8 $ hcPassword creds)
    req0
    manager
  case ereq of
    Left e -> do
      prettyWarn $
           flow "No HTTP digest prompt found, this will probably fail."
        <> blankLine
        <> string
             ( case fromException e of
                 Just e' -> displayDigestAuthException e'
                 Nothing -> displayException e
             )
      pure req0
    Right req -> pure req

-- | Upload a single tarball with the given @Uploader@.  Instead of
-- sending a file like 'upload', this sends a lazy bytestring.
--
-- Since 0.1.2.1
uploadBytes :: HasTerm m
            => String -- ^ Hackage base URL
            -> HackageAuth
            -> String -- ^ tar file name
            -> UploadVariant
            -> L.ByteString -- ^ tar file contents
            -> RIO m ()
uploadBytes baseUrl auth tarName uploadVariant bytes = do
  let req1 = setRequestHeader
               "Accept"
               ["text/plain"]
               (fromString
                  $  baseUrl
                  <> "packages/"
                  <> case uploadVariant of
                       Publishing -> ""
                       Candidate -> "candidates/"
               )
      formData = [partFileRequestBody "package" tarName (RequestBodyLBS bytes)]
  req2 <- liftIO $ formDataBody formData req1
  req3 <- applyAuth auth req2
  prettyInfoL
    [ "Uploading"
    , style Current (fromString tarName) <> "..."
    ]
  hFlush stdout
  withRunInIO $ \runInIO -> withResponse req3 (runInIO . inner)
 where
  inner :: HasTerm m => Response (ConduitM () S.ByteString IO ()) -> RIO m ()
  inner res =
    case getResponseStatusCode res of
      200 -> prettyInfoS "done!"
      401 -> do
        case auth of
          HACreds creds ->
            handleIO
              (const $ pure ())
              (liftIO $ removeFile (hcCredsFile creds))
          _ -> pure ()
        prettyThrowIO AuthenticationFailure
      403 -> do
        prettyError $
          "[S-2804]"
          <> line
          <> flow "forbidden upload"
          <> line
          <> flow "Usually means: you've already uploaded this package/version \
                  \combination. Ignoring error and continuing. The full \
                  \message from Hackage is below:"
          <> blankLine
        liftIO $ printBody res
      503 -> do
        prettyError $
          "[S-4444]"
          <> line
          <> flow "service unavailable"
          <> line
          <> flow "This error some times gets sent even though the upload \
                  \succeeded. Check on Hackage to see if your package is \
                  \present. The full message form Hackage is below:"
          <> blankLine
        liftIO $ printBody res
      code -> do
        let resBody = mapOutput show (getResponseBody res)
        resBody' <- liftIO $ runConduit $ resBody .| sinkList
        prettyThrowIO (ArchiveUploadFailure code resBody' tarName)

printBody :: Response (ConduitM () S.ByteString IO ()) -> IO ()
printBody res = runConduit $ getResponseBody res .| CB.sinkHandle stdout

-- | Upload a single tarball with the given @Uploader@.
--
-- Since 0.1.0.0
upload :: (HasLogFunc m, HasTerm m)
       => String -- ^ Hackage base URL
       -> HackageAuth
       -> FilePath
       -> UploadVariant
       -> RIO m ()
upload baseUrl auth fp uploadVariant =
  uploadBytes baseUrl auth (takeFileName fp) uploadVariant
    =<< liftIO (L.readFile fp)

uploadRevision :: (HasLogFunc m, HasTerm m)
               => String -- ^ Hackage base URL
               -> HackageAuth
               -> PackageIdentifier
               -> L.ByteString
               -> RIO m ()
uploadRevision baseUrl auth ident@(PackageIdentifier name _) cabalFile = do
  req0 <- parseRequest $ concat
    [ baseUrl
    , "package/"
    , packageIdentifierString ident
    , "/"
    , packageNameString name
    , ".cabal/edit"
    ]
  req1 <- formDataBody
    [ partLBS "cabalfile" cabalFile
    , partBS "publish" "on"
    ]
    req0
  req2 <- applyAuth auth req1
  void $ httpNoBody req2
