module DFDB.Database where

import ClassyPrelude
import Control.Lens (_Just, assign, at, modifying, over, use, view)
import Control.Monad.Except (MonadError, runExceptT, throwError)
import Control.Monad.State (MonadState)
import Data.Aeson (encode)
import Data.List ((!!), elemIndex)

import qualified DFDB.Types

emptyDatabase :: DFDB.Types.Database
emptyDatabase = DFDB.Types.Database mempty

getTable :: MonadState DFDB.Types.Database m => DFDB.Types.TableName -> m (Maybe DFDB.Types.Table)
getTable tableName = use (DFDB.Types.databaseTables . at tableName)

getTableOrFail :: (MonadError DFDB.Types.StatementFailureCode m, MonadState DFDB.Types.Database m) => DFDB.Types.TableName -> m DFDB.Types.Table
getTableOrFail tableName = maybe (throwError (DFDB.Types.StatementFailureCodeSyntaxError "Table does not exist")) pure
  =<< getTable tableName

execute :: MonadState DFDB.Types.Database m => DFDB.Types.Statement -> m DFDB.Types.StatementResult
execute = \ case
  DFDB.Types.StatementSelect cols tableName -> do
    result <- runExceptT $ do
      table <- getTableOrFail tableName
      columnIndices <- for cols $ \ col -> case elemIndex col (view DFDB.Types.tableColumns table) of
        Nothing -> throwError $ DFDB.Types.StatementFailureCodeSyntaxError $ "Column " <> DFDB.Types.unColumn col <> " does not exist in " <> DFDB.Types.unTableName tableName
        Just c -> pure c
      let rows = flip map (view DFDB.Types.tableRows table) $ \ (DFDB.Types.Row atoms) -> flip map columnIndices $ \ columnIndex -> atoms !! columnIndex
      pure . DFDB.Types.StatementResultSuccess . DFDB.Types.Output . unlines . map (decodeUtf8 . toStrict . encode) $ rows
    case result of
      Left code -> pure $ DFDB.Types.StatementResultFailure code
      Right x -> pure x
  DFDB.Types.StatementInsert row tableName -> do
    result <- runExceptT $ do
      table <- getTableOrFail tableName
      case length (DFDB.Types.unRow row) == length (view DFDB.Types.tableColumns table) of
        True -> assign (DFDB.Types.databaseTables . at tableName . _Just) (over DFDB.Types.tableRows (row:) table)
        False -> throwError $ DFDB.Types.StatementFailureCodeSyntaxError "Wrong number of columns"
    case result of
      Left code -> pure $ DFDB.Types.StatementResultFailure code
      Right () -> pure $ DFDB.Types.StatementResultSuccess $ DFDB.Types.Output "INSERT 1"
  DFDB.Types.StatementCreate tableName cols -> do
    use (DFDB.Types.databaseTables . at tableName) >>= \ case
      Nothing -> do
        modifying DFDB.Types.databaseTables (insertMap tableName $ DFDB.Types.Table tableName cols [])
        pure $ DFDB.Types.StatementResultSuccess $ DFDB.Types.Output "CREATE TABLE"
      Just _ -> pure $ DFDB.Types.StatementResultFailure $ DFDB.Types.StatementFailureCodeSyntaxError "Table already exists"

