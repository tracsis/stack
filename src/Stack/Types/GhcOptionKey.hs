{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}

module Stack.Types.GhcOptionKey
  ( GhcOptionKey (..)
  ) where

import qualified Data.Text as T
import           Pantry.Internal.AesonExtended
                   ( FromJSONKey (..), FromJSONKeyFunction (..) )
import           Stack.Prelude

data GhcOptionKey
  = GOKOldEverything
  | GOKEverything
  | GOKLocals
  | GOKTargets
  | GOKPackage !PackageName
  deriving (Eq, Ord)

instance FromJSONKey GhcOptionKey where
  fromJSONKey = FromJSONKeyTextParser $ \t ->
    case t of
      "*" -> pure GOKOldEverything
      "$everything" -> pure GOKEverything
      "$locals" -> pure GOKLocals
      "$targets" -> pure GOKTargets
      _ ->
        case parsePackageName $ T.unpack t of
          Nothing -> fail $ "Invalid package name: " ++ show t
          Just x -> pure $ GOKPackage x
  fromJSONKeyList =
    FromJSONKeyTextParser $ \_ -> fail "GhcOptionKey.fromJSONKeyList"
