{-# LANGUAGE QuasiQuotes #-}

module Main (main) where

import Control.Monad (unless, void)
import Data.Foldable (for_)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Effectful (Eff, IOE, MonadIO (liftIO), runEff, type (:>))
import Effectful.Concurrent qualified as ECC
import Effectful.Concurrent.Async qualified as EAsync
import Effectful.Dispatch.Dynamic (interpret, interpret_, localSeqUnlift)
import Effectful.Dynamic.Utils (ShowEffect (showEffectCons))
import Effectful.FileSystem.FileReader.Static qualified as FR
import Effectful.FileSystem.PathReader.Static (PathReader)
import Effectful.FileSystem.PathReader.Static qualified as PR
import Effectful.FileSystem.PathWriter.Static qualified as PW
import Effectful.Optparse.Static qualified as EOA
import Effectful.Process (Process)
import Effectful.Process qualified as EProcess
import Effectful.Terminal.Dynamic
  ( Terminal (GetTerminalSize),
    Window (Window, height, width),
  )
import FileSystem.OsPath
  ( OsPath,
    decodeLenient,
    decodeThrowM,
    ospPathSep,
    (</>),
  )
import Monitor (runMonitor)
import Monitor.Logger (RegionLogger (DisplayRegions, LogRegion, WithRegion))
import System.Environment qualified as Env
import System.Environment.Guard (ExpectEnv (ExpectEnvSet), guardOrElse')
import System.Timeout qualified as TO
import Test.Tasty
  ( TestTree,
    defaultMain,
    testGroup,
    withResource,
  )
import Test.Tasty.HUnit (HasCallStack, assertFailure, testCase)

main :: IO ()
main =
  defaultMain (withResource setup teardown tests)
  where
    tests getTestArgs =
      testGroup
        "Functional"
        [ testMonitor getTestArgs,
          testMonitorShortWindow getTestArgs
        ]

testMonitor :: IO TestArgs -> TestTree
testMonitor getTestArgs = testCase "Monitors build output" $ do
  buildPath <- decodeThrowM =<< (.buildFile) <$> getTestArgs
  logs <- runMonitorLogs getTestArgs (args buildPath)

  for_ expected $ \e -> do
    unless (e `Set.member` logs) $ do
      let msg =
            T.unpack $
              mconcat
                [ "*** Did not find log: ***\n\n",
                  e,
                  "\n\n*** In logs: ***\n\n",
                  T.intercalate "\n\n" (Set.toList logs)
                ]
      assertFailure msg
  where
    args p =
      [ "--file",
        p,
        "--period",
        "1"
      ]

    expected = [e1, e2, e3, e4, e5]

    e1 =
      T.unlines
        [ "To Build: 5",
          "  - bits-0.6",
          "  - byteable-0.1.1",
          "  - indexed-profunctors-0.1.1.1",
          "  - mtl-compat-0.2.2",
          "  - string-qq-0.0.6",
          "",
          "Building: 0",
          "",
          "Completed: 0"
        ]
    e2 =
      T.unlines
        [ "To Build: 2",
          "  - mtl-compat-0.2.2",
          "  - string-qq-0.0.6",
          "",
          "Building: 3",
          "  - bits-0.6",
          "  - byteable-0.1.1",
          "  - indexed-profunctors-0.1.1.1",
          "",
          "Completed: 0"
        ]

    e3 =
      T.unlines
        [ "To Build: 1",
          "  - string-qq-0.0.6",
          "",
          "Building: 4",
          "  - bits-0.6",
          "  - byteable-0.1.1",
          "  - indexed-profunctors-0.1.1.1",
          "  - mtl-compat-0.2.2",
          "",
          "Completed: 0"
        ]

    e4 =
      T.unlines
        [ "To Build: 1",
          "  - string-qq-0.0.6",
          "",
          "Building: 2",
          "  - indexed-profunctors-0.1.1.1",
          "  - mtl-compat-0.2.2",
          "",
          "Completed: 2",
          "  - bits-0.6",
          "  - byteable-0.1.1"
        ]

    e5 =
      T.unlines
        [ "To Build: 0",
          "",
          "Building: 2",
          "  - mtl-compat-0.2.2",
          "  - string-qq-0.0.6",
          "",
          "Completed: 3",
          "  - bits-0.6",
          "  - byteable-0.1.1",
          "  - indexed-profunctors-0.1.1.1"
        ]

testMonitorShortWindow :: IO TestArgs -> TestTree
testMonitorShortWindow getTestArgs = testCase "Monitors with short window" $ do
  testArgs <- getTestArgs
  buildPath <- decodeThrowM testArgs.buildFile

  let testArgs' =
        testArgs
          { mWindow =
              Just
                ( Window
                    { height = 8,
                      width = 80
                    }
                )
          }

  logs <- runMonitorLogs (pure testArgs') (args buildPath)

  for_ expected $ \e -> do
    unless (e `Set.member` logs) $ do
      let msg =
            T.unpack $
              mconcat
                [ "*** Did not find log: ***\n\n",
                  e,
                  "\n\n*** In logs: ***\n\n",
                  T.intercalate "\n\n" (Set.toList logs)
                ]
      assertFailure msg
  where
    args p =
      [ "--file",
        p,
        "--period",
        "1"
      ]

    expected = [e1, e2, e3, e4, e5]

    e1 =
      T.unlines
        [ "To Build: 5",
          "  - bits-0.6, byteable-0.1.1, indexed-profunctors-0.1.1.1, mtl-compat-0.2.2",
          "  - string-qq-0.0.6",
          "",
          "Building: 0",
          "",
          "Completed: 0"
        ]
    e2 =
      T.unlines
        [ "To Build: 2",
          "  - mtl-compat-0.2.2, string-qq-0.0.6",
          "",
          "Building: 3",
          "  - bits-0.6, byteable-0.1.1, indexed-profunctors-0.1.1.1",
          "",
          "Completed: 0"
        ]

    e3 =
      T.unlines
        [ "To Build: 1",
          "  - string-qq-0.0.6",
          "",
          "Building: 4",
          "  - bits-0.6, byteable-0.1.1, indexed-profunctors-0.1.1.1, mtl-compat-0.2.2",
          "",
          "Completed: 0"
        ]

    e4 =
      T.unlines
        [ "To Build: 1",
          "  - string-qq-0.0.6",
          "",
          "Building: 2",
          "  - indexed-profunctors-0.1.1.1, mtl-compat-0.2.2",
          "",
          "Completed: 2",
          "  - bits-0.6, byteable-0.1.1"
        ]

    e5 =
      T.unlines
        [ "To Build: 0",
          "",
          "Building: 2",
          "  - mtl-compat-0.2.2, string-qq-0.0.6",
          "",
          "Completed: 3",
          "  - bits-0.6, byteable-0.1.1, indexed-profunctors-0.1.1.1"
        ]

type Unit = ()

runMonitorLogs :: (HasCallStack) => IO TestArgs -> [String] -> IO (Set Text)
runMonitorLogs getTestArgs cliArgs = do
  testArgs <- getTestArgs
  logsRef <- newIORef mempty
  _ <-
    TO.timeout 10_000_000 $
      ( Env.withArgs cliArgs $ runner logsRef testArgs.mWindow $ do
          (runBuildScript getTestArgs)
            `EAsync.concurrently`
            -- start this second so build file exists.
            (ECC.threadDelay 500_000 *> Monitor.runMonitor Unit)
      )
  readIORef logsRef
  where
    runner ref mWindow =
      runEff
        . ECC.runConcurrent
        . EProcess.runProcess
        . runTerminalMock mWindow
        . runRegionLoggerMock ref
        . PR.runPathReader
        . FR.runFileReader
        . EOA.runOptparse

runRegionLoggerMock ::
  forall r es a.
  ( r ~ (),
    HasCallStack,
    IOE :> es
  ) =>
  IORef (Set Text) ->
  Eff (RegionLogger r : es) a ->
  Eff es a
runRegionLoggerMock logsRef = interpret $ \env -> \case
  LogRegion _ _ t -> writeLogs t
  WithRegion _ onRegion -> localSeqUnlift env $ \unlift ->
    unlift (onRegion ())
  DisplayRegions m -> localSeqUnlift env $ \unlift -> unlift m
  where
    writeLogs :: Text -> Eff es ()
    writeLogs txt = liftIO $ do
      modifyIORef' logsRef (\st -> Set.insert txt st)

runTerminalMock :: (Integral b) => Maybe (Window b) -> Eff (Terminal : es) a -> Eff es a
runTerminalMock mWindow = interpret_ $ \case
  GetTerminalSize ->
    pure $ case mWindow of
      Just window ->
        Window
          { height = fromIntegral window.height,
            width = fromIntegral window.width
          }
      Nothing -> Window {height = 80, width = 100}
  other -> error $ showEffectCons other

runBuildScript ::
  ( IOE :> es,
    HasCallStack,
    PathReader :> es,
    Process :> es
  ) =>
  IO TestArgs ->
  Eff es ()
runBuildScript getTestArgs = do
  testArgs <- liftIO $ getTestArgs

  pwd <- PR.getCurrentDirectory
  scriptPath <- decodeThrowM (pwd </> [ospPathSep|test/functional/build.sh|])

  outPath <- decodeThrowM testArgs.buildFile

  void $ EProcess.createProcess $ EProcess.proc scriptPath [outPath]

data TestArgs = MkTestArgs
  { tmpDir :: OsPath,
    buildFile :: OsPath,
    mWindow :: Maybe (Window Int)
  }

setup :: (HasCallStack) => IO TestArgs
setup = runTestEff $ do
  tmpDir <- (</> [ospPathSep|build-monitor|]) <$> PR.getTemporaryDirectory

  PW.removePathForciblyIfExists_ tmpDir

  PW.createDirectoryIfMissing True tmpDir

  let buildFile = tmpDir </> [ospPathSep|build.txt|]

  pure $ MkTestArgs tmpDir buildFile Nothing

teardown :: (HasCallStack) => TestArgs -> IO ()
teardown testArgs = do
  let cleanup = runTestEff . PW.removePathForciblyIfExists_ $ testArgs.tmpDir
      doNothing =
        putStrLn $
          "*** Not cleaning up tmp dir: '"
            <> decodeLenient testArgs.tmpDir
            <> "'"

  guardOrElse' "NO_CLEANUP" ExpectEnvSet doNothing cleanup

runTestEff ::
  (HasCallStack) =>
  Eff [PR.PathReader, PW.PathWriter, IOE] a -> IO a
runTestEff =
  runEff
    . PW.runPathWriter
    . PR.runPathReader
