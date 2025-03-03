module Monitor.Args
  ( Args (..),
    getArgs,
  )
where

import Data.List qualified as L
import Data.String (IsString (fromString))
import Data.Version (Version (versionBranch))
import Effectful (Eff, (:>))
import Effectful.Dispatch.Dynamic (HasCallStack)
import Effectful.Optparse.Static (Optparse)
import Effectful.Optparse.Static qualified as EOA
import FileSystem.OsPath (OsPath)
import FileSystem.OsPath qualified as OsPath
import Options.Applicative
  ( Mod,
    Parser,
    ParserInfo
      ( ParserInfo,
        infoFailureCode,
        infoFooter,
        infoFullDesc,
        infoHeader,
        infoParser,
        infoPolicy,
        infoProgDesc
      ),
    (<**>),
  )
import Options.Applicative qualified as OA
import Options.Applicative.Help (Chunk (Chunk))
import Options.Applicative.Help.Chunk qualified as Chunk
import Options.Applicative.Help.Pretty qualified as Pretty
import Options.Applicative.Types (ArgPolicy (Intersperse))
import Paths_build_monitor_hs qualified as Paths

-- | CLI args.
data Args = MkArgs
  { compact :: Maybe Int,
    filePath :: OsPath,
    period :: Maybe Int
  }
  deriving stock (Eq, Show)

getArgs :: (HasCallStack, Optparse :> es) => Eff es Args
getArgs = EOA.execParser parserInfo

-- | Optparse-Applicative info.
parserInfo :: ParserInfo Args
parserInfo =
  ParserInfo
    { infoParser = argsParser,
      infoFullDesc = True,
      infoProgDesc = desc,
      infoHeader = Chunk header,
      infoFooter = Chunk footerTxt,
      infoFailureCode = 1,
      infoPolicy = Intersperse
    }
  where
    header = Just "Build-monitor: Monitors haskell builds"
    footerTxt = Just $ fromString versNum
    desc =
      Chunk.paragraph $
        mconcat
          [ "Build-monitor monitors a haskell output build file (e.g. cabal ",
            "build > out.txt) and reports basic progress information."
          ]

argsParser :: Parser Args
argsParser =
  MkArgs
    <$> compactParser
    <*> filePathParser
    <*> periodParser
      <**> OA.helper
      <**> version

compactParser :: Parser (Maybe Int)
compactParser =
  OA.optional
    $ OA.option
      OA.auto
    $ mconcat
      [ OA.long "compact",
        OA.metavar "NAT",
        mkHelp $
          mconcat
            [ "Compacts lines to save vertical space, with line length ",
              "limited by the parameter. If not given, we attempt to choose ",
              "compact vs. default based on available terminal space."
            ]
      ]

filePathParser :: Parser OsPath
filePathParser =
  OA.option
    readPath
    $ mconcat
      [ OA.short 'f',
        OA.long "file",
        OA.metavar "PATH",
        mkHelp "Path to file to monitor."
      ]
  where
    readPath = OA.str >>= OsPath.encodeFail

periodParser :: Parser (Maybe Int)
periodParser =
  OA.optional
    $ OA.option
      OA.auto
    $ mconcat
      [ OA.short 'p',
        OA.long "period",
        OA.metavar "NAT",
        mkHelp "Monitor refresh period, in seconds."
      ]

version :: Parser (a -> a)
version = OA.infoOption versNum (OA.long "version" <> OA.short 'v' <> OA.hidden)

versNum :: String
versNum = "Version: " <> L.intercalate "." (show <$> versionBranch Paths.version)

mkHelp :: String -> Mod f a
mkHelp s = mkMultiHelp [s]

mkMultiHelp :: [String] -> Mod f a
mkMultiHelp =
  OA.helpDoc
    . fmap (<> Pretty.hardline)
    . Chunk.unChunk
    . Chunk.vsepChunks
    . fmap Chunk.paragraph
