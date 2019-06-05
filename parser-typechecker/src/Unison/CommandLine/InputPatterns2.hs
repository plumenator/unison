{-# LANGUAGE DoAndIfThenElse     #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE ViewPatterns        #-}


module Unison.CommandLine.InputPatterns2 where

-- import Debug.Trace
import Data.Bifunctor (first)
import Data.List (intercalate)
import Data.String (fromString)
import Unison.Codebase.Editor.Input (Input)
import Unison.CommandLine
import Unison.CommandLine.InputPattern2 (ArgumentType (ArgumentType), InputPattern (InputPattern), IsOptional(Optional,Required,ZeroPlus,OnePlus))
import Unison.Util.Monoid (intercalateMap)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Unison.Codebase as Codebase
import qualified Unison.Codebase.Branch2 as Branch
import qualified Unison.Codebase.Editor.HandleInput as HI
import qualified Unison.Codebase.Editor.Input as Input
import qualified Unison.Codebase.Path as Path
import qualified Unison.CommandLine.InputPattern2 as I
import qualified Unison.HashQualified as HQ
import qualified Unison.Names as Names
import qualified Unison.Util.ColorText as CT
import qualified Unison.Util.Pretty as P

showPatternHelp :: InputPattern -> P.Pretty CT.ColorText
showPatternHelp i = P.lines [
  P.bold (fromString $ I.patternName i) <> fromString
    (if not . null $ I.aliases i
     then " (or " <> intercalate ", " (I.aliases i) <> ")"
     else ""),
  P.wrap $ I.help i ]

-- `example list ["foo", "bar"]` (haskell) becomes `list foo bar` (pretty)
makeExample :: InputPattern -> [P.Pretty CT.ColorText] -> P.Pretty CT.ColorText
makeExample p args =
  backtick (intercalateMap " " id (fromString (I.patternName p) : args))

makeExample' :: InputPattern -> P.Pretty CT.ColorText
makeExample' p = makeExample p []

makeExampleEOS ::
  InputPattern -> [P.Pretty CT.ColorText] -> P.Pretty CT.ColorText
makeExampleEOS p args = P.group $
  backtick (intercalateMap " " id (fromString (I.patternName p) : args)) <> "."

helpFor :: InputPattern -> Either (P.Pretty CT.ColorText) Input
helpFor p = I.parse help [I.patternName p]

updateBuiltins :: InputPattern
updateBuiltins = InputPattern "builtins.update" [] []
  "Adds all the builtins that are missing from this branch, and deprecate the ones that don't exist in this version of Unison."
  (const . pure $ Input.UpdateBuiltinsI)

todo :: InputPattern
todo = InputPattern "todo"
  []
  [(Required, patchPathArg), (Optional, branchPathArg)]
  "`todo` lists the work remaining in the current branch to complete an ongoing refactoring."
  (\ws -> case ws of
    patchStr : ws -> first fromString $ do
      patch <- Path.parseSplit' patchStr
      branch <- case ws of
        [pathStr] -> Path.parsePath' pathStr
        _ -> pure Path.relativeEmpty'
      pure $ Input.TodoI patch branch
    [] -> Left $ warn "`todo` takes a patch and an optional path")

add :: InputPattern
add = InputPattern "add" [] [(ZeroPlus, noCompletions)]
 "`add` adds to the codebase all the definitions from the most recently typechecked file."
 (\ws -> pure $ Input.AddI (HQ.fromString <$> ws))

update :: InputPattern
update = InputPattern "update"
  []
  [(Required, patchPathArg)
  ,(ZeroPlus, noCompletions)]
  "`update` works like `add`, except if a definition in the file has the same name as an existing definition, the name gets updated to point to the new definition. If the old definition has any dependents, `update` will add those dependents to a refactoring session."
  (\ws -> case ws of
    patchStr : ws -> first fromString $ do
      patch <- Path.parseSplit' patchStr
      pure $ Input.UpdateI patch (HQ.fromString <$> ws)
    [] -> Left $ warn "`update` takes a patch and an optional list of definitions")

patch :: InputPattern
patch = InputPattern "patch" [] [(Required, patchPathArg), (Optional, branchPathArg)]
  "`propagate` rewrites any definitions that depend on definitions with type-preserving edits to use the updated versions of these dependencies."
  (\ws -> case ws of
    patchStr : ws -> first fromString $ do
      patch <- Path.parseSplit' patchStr
      branch <- case ws of
        [pathStr] -> Path.parsePath' pathStr
        _ -> pure Path.relativeEmpty'
      pure $ Input.PropagateI patch branch
    [] -> Left $ warn "`todo` takes a patch and an optional path")


view :: InputPattern
view = InputPattern "view" [] [(OnePlus, exactDefinitionQueryArg)]
      "`view foo` prints the definition of `foo`."
      (pure . Input.ShowDefinitionI Input.ConsoleLocation)

viewByPrefix :: InputPattern
viewByPrefix
  = InputPattern "view.recursive" [] [(OnePlus, exactDefinitionQueryArg)]
    "`view.recursive Foo` prints the definitions of `Foo` and `Foo.blah`."
    (pure . Input.ShowDefinitionByPrefixI Input.ConsoleLocation)

find :: InputPattern
find = InputPattern "find" [] [(ZeroPlus, fuzzyDefinitionQueryArg)]
    (P.wrapColumn2
      [ ("`find`"
        , "lists all definitions in the current branch.")
      , ( "`find foo`"
        , "lists all definitions with a name similar to 'foo' in the current branch.")
      , ( "`find foo bar`"
        , "lists all definitions with a name similar to 'foo' or 'bar' in the current branch.")
      , ( "`find -l foo bar`"
        , "lists all definitions with a name similar to 'foo' or 'bar' in the current branch, along with their hashes and aliases.")
      ]
    )
    (pure . Input.SearchByNameI)

renameTerm :: InputPattern
renameTerm = InputPattern "rename.term" []
    [(Required, exactDefinitionTermQueryArg)
    ,(Required, noCompletions)]
    "`rename.term foo bar` renames `foo` to `bar`."
    (\case
      [oldName, newName] -> first fromString $ do
        src <- Path.parseHQ'Split' oldName
        target <- Path.parseSplit' newName
        pure $ Input.MoveTermI src target
      _ -> Left . P.warnCallout $ P.wrap
        "`rename.term` takes two arguments, like `rename oldname newname`.")

deleteTerm :: InputPattern
deleteTerm = InputPattern "delete.term" []
    [(OnePlus, exactDefinitionTermQueryArg)]
    "`delete.term foo` removes the term name `foo` from the namespace."
    (\case
      [query] -> first fromString $ do
        p <- Path.parseHQ'Split' query
        pure $ Input.DeleteTermI p
      _ -> Left . P.warnCallout $ P.wrap
        "`delete.term` takes one or more arguments, like `delete.term name`."
    )

aliasTerm :: InputPattern
aliasTerm = InputPattern "alias.term" []
    [(Required, exactDefinitionTermQueryArg), (Required, noCompletions)]
    "`alias.term foo bar` introduces `bar` with the same definition as `foo`."
    (\case
      [oldName, newName] -> first fromString $ do
        source <- Path.parseHQSplit' oldName
        target <- Path.parseSplit' newName
        pure $ Input.AliasTermI source target
      _ -> Left . warn $ P.wrap
        "`alias.term` takes two arguments, like `alias.term oldname newname`."
    )

cd :: InputPattern
cd = InputPattern "cd" [] [(Required, branchArg)]
    (P.wrapColumn2
      [ ("`cd foo.bar`",
          "descends into foo.bar from the current path.")
      , ("`cd .cat.dog",
          "sets the current path to the abolute path .cat.dog.") ])
    (\case
      [p] -> first fromString $ do
        p <- Path.parsePath' p
        pure . Input.SwitchBranchI $ p
      _ -> Left (I.help cd)
    )

deleteBranch :: InputPattern
deleteBranch = InputPattern "branch.delete" [] [(OnePlus, branchArg)]
  "`branch.delete <foo>` deletes the branch `foo`"
   (\case
        [p] -> first fromString $ do
          p <- Path.parseSplit' p
          pure . Input.DeleteBranchI $ p
        _ -> Left (I.help deleteBranch)
      )

forkLocal :: InputPattern
forkLocal = InputPattern "fork" [] [(Required, branchArg)
                                   ,(Required, branchArg)]
    "`fork foo bar` creates the branch `bar` as a fork of `foo`."
    (\case
      [src, dest] -> first fromString $ do
        src <- Path.parseSplit' src
        dest <- Path.parsePath' dest
        pure $ Input.ForkLocalBranchI src dest
      _ -> Left (I.help forkLocal)
    )

mergeLocal :: InputPattern
mergeLocal = InputPattern "merge" [] [(Required, branchArg)
                                     ,(Optional, branchArg)]
 "`merge foo` merges the branch 'foo' into the current branch."
 (\case
      [src] -> first fromString $ do
        src <- Path.parseSplit' src
        pure $ Input.ForkLocalBranchI src Path.relativeEmpty'
      [src, dest] -> first fromString $ do
        src <- Path.parseSplit' src
        dest <- Path.parsePath' dest
        pure $ Input.ForkLocalBranchI src dest
      _ -> Left (I.help mergeLocal)
 )

-- replace,resolve :: InputPattern
--replace = InputPattern "replace" []
--          [ (Required, exactDefinitionQueryArg)
--          , (Required, exactDefinitionQueryArg) ]
--  (makeExample replace ["foo#abc", "foo#def"] <> "begins a refactor to replace" <> "uses of `foo#abc` with `foo#def`")
--  (const . Left . warn . P.wrap $ "This command hasn't been implemented. 😞")
--
--resolve = InputPattern "resolve" [] [(Required, exactDefinitionQueryArg)]
--  (makeExample resolve ["foo#abc"] <> "sets `foo#abc` as the canonical `foo` in cases of conflict, and begins a refactor to replace references to all other `foo`s to `foo#abc`.")
--  (const . Left . warn . P.wrap $ "This command hasn't been implemented. 😞")

edit :: InputPattern
edit = InputPattern "edit" [] [(OnePlus, exactDefinitionQueryArg)]
  "`edit foo` prepends the definition of `foo` to the top of the most recently saved file."
  (pure . Input.ShowDefinitionI Input.LatestFileLocation)

help :: InputPattern
help = InputPattern
    "help" ["?"] [(Optional, commandNameArg)]
    "`help` shows general help and `help <cmd>` shows help for one command."
    (\case
      [] -> Left $ intercalateMap "\n\n" showPatternHelp validInputs
      [cmd] -> case lookup cmd (commandNames `zip` validInputs) of
        Nothing  -> Left . warn $ "I don't know of that command. Try `help`."
        Just pat -> Left $ I.help pat
      _ -> Left $ warn "Use `help <cmd>` or `help`.")

quit = InputPattern "quit" ["exit"] []
  "Exits the Unison command line interface."
  (\case
    [] -> pure Input.QuitI
    _  -> Left "Use `quit`, `exit`, or <Ctrl-D> to quit."
  )

validInputs :: [InputPattern]
validInputs =
  [ help
  , add
  , update
  , forkLocal
  , mergeLocal
  , deleteBranch
  , find
  , view
  , edit
  , renameTerm
  , deleteTerm
  , aliasTerm
  , todo
  , patch
  --  , InputPattern "test" [] []
  --    "`test` runs unit tests for the current branch."
  --    (const $ pure $ Input.TestI True True)g
  , InputPattern "execute" [] []
    "`execute foo` evaluates the Unison expression `foo` of type `()` with access to the `IO` ability."
    (\ws -> if null ws
               then Left $ warn "`execute` needs a Unison language expression."
               else pure . Input.ExecuteI $ intercalate " " ws)
  , quit
  , updateBuiltins
--  , InputPattern "edit.list" [] []
--      "Lists all the edits in the current branch."
--      (const . pure $ Input.ListEditsI)
  ]

allTargets :: Set.Set Names.NameTarget
allTargets = Set.fromList [Names.TermName, Names.TypeName]

commandNames :: [String]
commandNames = I.patternName <$> validInputs

commandNameArg :: ArgumentType
commandNameArg =
  ArgumentType "command" $ \q _ _ -> pure (fuzzyComplete q commandNames)

branchArg :: ArgumentType
branchArg = ArgumentType "branch" $ \q codebase _b -> do
  branches <- Codebase.branches codebase
  let bs = Text.unpack <$> branches
  pure $ fuzzyComplete q bs

fuzzyDefinitionQueryArg :: ArgumentType
fuzzyDefinitionQueryArg =
  ArgumentType "fuzzy definition query" $ \q _ (Branch.head -> b) -> do
    pure $ [] -- fuzzyCompleteHashQualified b q

-- todo: support absolute paths?
exactDefinitionQueryArg :: ArgumentType
exactDefinitionQueryArg =
  ArgumentType "definition query" $ \q _ (Branch.head -> b) -> do
    pure $ [] -- autoCompleteHashQualified b q

exactDefinitionTypeQueryArg :: ArgumentType
exactDefinitionTypeQueryArg =
  ArgumentType "term definition query" $ \q _ (Branch.head -> b) -> do
    pure $ [] -- autoCompleteHashQualifiedType b q

exactDefinitionTermQueryArg :: ArgumentType
exactDefinitionTermQueryArg =
  ArgumentType "term definition query" $ \q _ (Branch.head -> b) -> do
    pure $ [] -- autoCompleteHashQualifiedTerm b q

patchPathArg :: ArgumentType
patchPathArg = noCompletions { I.typeName = "patch" }
  -- todo - better autocomplete provider here
  -- ArgumentType "patch" $ \q ->

branchPathArg :: ArgumentType
branchPathArg = noCompletions { I.typeName = "branch" }

noCompletions :: ArgumentType
noCompletions = ArgumentType "word" I.noSuggestions
