{-# LANGUAGE LambdaCase #-}

module Restyled.Backend.Health
    ( runHealthChecks
    )
where

import Restyled.Prelude

import Data.List (genericLength)
import qualified Data.Text as T
import Restyled.Models
import Restyled.TimeRange

data Stat = Count Int | Rate (Maybe Double)

showStat :: Stat -> String
showStat = \case
    Count c -> show c
    Rate Nothing -> "N/A"
    Rate (Just r) -> show r <> "%"

data Health = Normal | Warning | Fatal
    deriving Show

data HealthCheck = HealthCheck
    { hcName :: Text
    , hcCompute :: [Entity Job] -> Stat
    , hcHealth :: Stat -> Health
    }

runHealthChecks :: (HasLogFunc env, HasDB env) => RIO env ()
runHealthChecks = do
    logInfoN "Running 60 minute HealthChecks"
    range <- timeRangeFromMinutesAgo 60
    jobs <- runDB $ selectListWithTimeRange JobCreatedAt range
    traverse_
        (runHealthCheck jobs)
        [ HealthCheck
            { hcName = "Jobs completed"
            , hcCompute = completions
            , hcHealth = \case
                Count 0 -> Fatal
                _ -> Normal
            }
        , HealthCheck
            { hcName = "Effective success rate"
            , hcCompute = errorRate [10, 11, 20]
            , hcHealth = thresholds (< 60) (< 80)
            }
        , HealthCheck
            { hcName = "Total success rate"
            , hcCompute = errorRate []
            , hcHealth = thresholds (< 40) (< 60)
            }
        ]

runHealthCheck :: (HasLogFunc env) => [Entity Job] -> HealthCheck -> RIO env ()
runHealthCheck jobs HealthCheck {..} = case health of
    Normal -> logInfoN message
    Warning -> logWarnN message
    Fatal -> logErrorN message
  where
    stat = hcCompute jobs
    health = hcHealth stat
    message = T.pack $ unwords
        [ "healthcheck=" <> show hcName
        , "health=" <> show health
        , "stat=" <> showStat stat
        ]

completions :: [Entity Job] -> Stat
completions = Count . length . mapMaybe (jobExitCode . entityVal)

errorRate
    :: [Int] -- ^ Exit codes to ignore
    -> [Entity Job]
    -> Stat
errorRate ignoreCodes jobs
    | total == 0 = Rate Nothing
    | otherwise = Rate $ Just $ (succeeded / total) * 100
  where
    exitCodes =
        filter (`notElem` ignoreCodes) $ mapMaybe (jobExitCode . entityVal) jobs
    total = genericLength exitCodes
    succeeded = genericLength $ filter (== 0) exitCodes

thresholds
    :: (Double -> Bool) -- ^ True if Fatal
    -> (Double -> Bool) -- ^ True if Warning
    -> Stat
    -> Health
thresholds isFatal isWarning stat
    | threshold isFatal stat = Fatal
    | threshold isWarning stat = Warning
    | otherwise = Normal

threshold :: (Double -> Bool) -> Stat -> Bool
threshold f = \case
    Count c -> f $ fromIntegral c
    Rate Nothing -> False
    Rate (Just r) -> f r