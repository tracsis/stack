{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE NoFieldSelectors  #-}

module Stack.Types.ExtraDirs
  ( ExtraDirs (..)
  ) where

import           Generics.Deriving.Monoid ( mappenddefault, memptydefault )
import           Stack.Prelude

data ExtraDirs = ExtraDirs
  { bins :: ![Path Abs Dir]
  , includes :: ![Path Abs Dir]
  , libs :: ![Path Abs Dir]
  }
  deriving (Show, Generic)

instance Semigroup ExtraDirs where
  (<>) = mappenddefault

instance Monoid ExtraDirs where
  mempty = memptydefault
  mappend = (<>)
