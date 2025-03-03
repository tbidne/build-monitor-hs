{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

module Main (main) where

import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as C8
import Effectful (Eff, IOE, runEff)
import Effectful.FileSystem.FileReader.Static qualified as FR
import Effectful.Terminal.Dynamic qualified as Term
import FileSystem.OsPath (OsPath, ospPathSep)
import GHC.Stack (HasCallStack)
import Monitor (Status)
import Monitor qualified
import TH qualified
import Test.Tasty.Bench
  ( Benchmark,
    bench,
    defaultMain,
    env,
    nf,
    nfIO,
  )

main :: IO ()
main = do
  defaultMain
    [ env (pure sampleLines) benchParseStatus,
      env (pure sampleStatus) benchFormatStatus,
      env (pure sampleStatus) benchFormatStatusCompact,
      benchReadFormatted samplePath,
      benchReadFormattedCompact samplePath
    ]

benchParseStatus :: [ByteString] -> Benchmark
benchParseStatus txtLines =
  bench "parseStatus" $ nf Monitor.parseStatus txtLines

benchFormatStatus :: Status -> Benchmark
benchFormatStatus status =
  bench "formatStatus" $ nf (Monitor.formatStatus Nothing) status

benchFormatStatusCompact :: Status -> Benchmark
benchFormatStatusCompact status =
  bench "formatStatus_compact" $ nf (Monitor.formatStatus (Just 80)) status

benchReadFormatted :: OsPath -> Benchmark
benchReadFormatted path =
  bench "readFormattedStatus" $
    nfIO (runBenchEff . Monitor.readFormattedStatus Nothing $ path)

benchReadFormattedCompact :: OsPath -> Benchmark
benchReadFormattedCompact path =
  bench "readFormattedStatus_compact" $
    nfIO (runBenchEff . Monitor.readFormattedStatus (Just 80) $ path)

samplePath :: OsPath
samplePath = [ospPathSep|./bench/sample.txt|]

sampleBS :: ByteString
sampleBS = $$TH.readSampleTH

sampleLines :: [ByteString]
sampleLines = C8.lines sampleBS

sampleStatus :: Status
sampleStatus = Monitor.parseStatus sampleLines

runBenchEff ::
  (HasCallStack) =>
  Eff [FR.FileReader, Term.Terminal, IOE] a ->
  IO a
runBenchEff = runEff . Term.runTerminal . FR.runFileReader
