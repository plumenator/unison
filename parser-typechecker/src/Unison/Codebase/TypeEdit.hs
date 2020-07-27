{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

module Unison.Codebase.TypeEdit where

import Unison.Reference (Reference, ReferenceH)
import qualified Unison.Reference as Reference
import Unison.Hashable (Hashable)
import qualified Unison.Hashable as H
import Unison.Hash (Hash)

type TypeEdit = TypeEditH Hash
data TypeEditH h = Replace (ReferenceH h) | Deprecate
  deriving (Eq, Ord)
deriving instance Show (ReferenceH h) => Show (TypeEditH h)  

hmap :: (h -> h') -> TypeEditH h -> TypeEditH h'
hmap f = \case
  Replace r -> Replace (Reference.hmap f r)
  Deprecate -> Deprecate

references :: TypeEdit -> [Reference]
references (Replace r) = [r]
references Deprecate = []

instance Hashable TypeEdit where
  tokens (Replace r) = H.Tag 0 : H.tokens r
  tokens Deprecate   = [H.Tag 1]

toReference :: TypeEdit -> Maybe Reference
toReference (Replace r) = Just r
toReference Deprecate     = Nothing
