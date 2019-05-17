{-# LANGUAGE PatternSynonyms #-}

module Unison.Codebase.SearchResult where

import           Data.Set             (Set)
import qualified Data.Set as Set
import           Unison.HashQualified (HashQualified)
import qualified Unison.HashQualified as HQ
import           Unison.Reference     (Reference)
import           Unison.Referent      (Referent)

-- this Ord instance causes types < terms
data SearchResult = Tp TypeResult | Tm TermResult deriving (Eq, Ord, Show)

data TermResult = TermResult
  { termName    :: HashQualified
  , referent    :: Referent
  , termAliases :: Set HashQualified
  } deriving (Eq, Ord, Show)

data TypeResult = TypeResult
  { typeName    :: HashQualified
  , reference   :: Reference
  , typeAliases :: Set HashQualified
  } deriving (Eq, Ord, Show)

pattern Tm' hq r as = Tm (TermResult hq r as)
pattern Tp' hq r as = Tp (TypeResult hq r as)

termResult :: HashQualified -> Referent -> Set HashQualified -> SearchResult
termResult hq r as = Tm (TermResult hq r as)

typeResult :: HashQualified -> Reference -> Set HashQualified -> SearchResult
typeResult hq r as = Tp (TypeResult hq r as)

name :: SearchResult -> HashQualified
name = \case
  Tm t -> termName t
  Tp t -> typeName t

aliases :: SearchResult -> Set HashQualified
aliases = \case
  Tm t -> termAliases t
  Tp t -> typeAliases t
