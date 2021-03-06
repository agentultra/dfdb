module DFDB.Application where

import ClassyPrelude
import Control.Lens (use)
import Control.Monad.State (execStateT)
import System.Exit (exitSuccess)

import DFDB.Database (emptyDatabase, execute)
import DFDB.Persist (dbDir, loadDatabase, saveDatabase)
import DFDB.Statement (parseStatement, runParser)
import qualified DFDB.Transaction
import qualified DFDB.Types

greeting :: MonadIO m => m ()
greeting = putStrLn . unlines $
  [ "Welcome to DFDB"
  ]

helpText :: MonadIO m => m ()
helpText = putStrLn . unlines $
  [ "Enter \"help\" to get this text"
  , "  Quit commands: " <> intercalate ", " (DFDB.Types.unCommand <$> quitCommands)
  ]

replPrompt :: MonadIO m => m ()
replPrompt = putStr "dfdb > " >> liftIO (hFlush stdout)

quitCommands :: [DFDB.Types.Command]
quitCommands =
  [ DFDB.Types.Command ":q"
  , DFDB.Types.Command "quit()"
  , DFDB.Types.Command "exit"
  ]

dfdbRepl :: IO ()
dfdbRepl = do
  greeting
  helpText

  db <- loadDatabase dbDir >>= \ case
    Nothing -> pure emptyDatabase
    Just (Right d) -> pure d
    Just (Left err) -> do
      putStrLn $ "Couldn't load database (" <> pack err <> "), creating a new one"
      pure emptyDatabase

  void . flip execStateT (DFDB.Types.TransactionalDatabase db Nothing) . forever $ do
    replPrompt
    input <- DFDB.Types.Command <$> liftIO getLine
    when (input `elem` quitCommands) $ do
      currentDb <- use DFDB.Types.transactionalDatabaseLastSavepoint
      saveDatabase dbDir currentDb
      liftIO exitSuccess
    case runParser parseStatement input of

      -- failed to parse command
      DFDB.Types.CommandOutputFailure code -> case code of
        DFDB.Types.CommandFailureCodeParser err -> do
          putStrLn $ "Unrecognized command " <> DFDB.Types.unCommand input <> " (" <> err <> ")"
          helpText

      -- successfully parsed command
      DFDB.Types.CommandOutputSuccess parsedStatement -> case parsedStatement of

        -- some repl command
        DFDB.Types.ParsedStatementHelp -> helpText

        -- some sql command
        DFDB.Types.ParsedStatement statement -> DFDB.Transaction.runTransaction (DFDB.Transaction.Transaction (execute statement)) >>= \ case
          Right output -> putStrLn $ DFDB.Types.unOutput output
          Left code -> case code of
            DFDB.Types.StatementFailureCodeSyntaxError err -> putStrLn err
            DFDB.Types.StatementFailureCodeInternalError err -> putStrLn err
