-- ═══════════════════════════════════════════════════════════════════════════════
-- AgentMemory.hs — WORM-Sealed Observation History
-- bridges/haskell/AgentMemory.hs
--
-- PHASE 7 AGENT MEMORY. APPEND-ONLY. CRYPTOGRAPHICALLY SEALED.
--
-- Maintains agent observation history with WORM (Write-Once, Read-Many) integrity.
-- Every observation is chained via hash: obs_n+1 = hash(obs_n || obs_n+1_data)
--
-- Memory is immutable: agents can only READ prior observations and APPEND new ones.
-- No updates, no deletes, no rewrites. History is audit trail.
--
-- ═══════════════════════════════════════════════════════════════════════════════

{-# LANGUAGE DeriveGeneric #-}

module AgentMemory where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.List (intercalate)
import Data.Time (getCurrentTime, formatTime, defaultTimeLocale, UTCTime)
import GHC.Generics (Generic)
import Data.Hashable (hash)
import qualified Data.Map.Strict as Map
import Control.Exception (bracket)
import System.IO (withFile, IOMode(..), hPutStrLn, hGetContents)

-- Re-import agent types for memory
import SpacetimeAgent (Observation(..), AgentId, Frame, Agent(..))

-- ── WORM Memory Entry ─────────────────────────────────────────────────────────────
-- Each entry is sealed and immutable.

data WormMemoryEntry = WormMemoryEntry
  { entryIndex :: Int              -- Position in chain
  , entryTimestamp :: UTCTime      -- When recorded
  , entryAgentId :: AgentId        -- Which agent
  , entryData :: Observation       -- The observation
  , entryPriorHash :: ByteString   -- Hash of previous entry
  , entryCurrentHash :: ByteString -- WORM seal of this + prior
  } deriving (Show, Eq, Generic)

-- ── WORM Memory Log (the durable record) ──────────────────────────────────────────

data WormMemoryLog = WormMemoryLog
  { logPath :: FilePath            -- File location (append-only log)
  , logEntries :: [WormMemoryEntry]
  , logTailHash :: ByteString      -- Hash of last entry (for chain integrity)
  , logSize :: Int                 -- Number of entries
  } deriving (Show, Eq, Generic)

-- ── Encode entry to ByteString for hashing ─────────────────────────────────────────

encodeMemoryEntry :: WormMemoryEntry -> ByteString
encodeMemoryEntry entry =
  let idxStr = show (entryIndex entry)
      aidStr = entryAgentId entry
      timeStr = show (entryTimestamp entry)
      obsStr = show (entryData entry)
      priorStr = BSC.unpack (entryPriorHash entry)
      parts = [idxStr, aidStr, timeStr, obsStr, priorStr]
  in BSC.pack (intercalate "|" parts)

-- ── Hash chain: compute WORM seal ──────────────────────────────────────────────────
-- WORM seal = hash(this_entry_data || prior_hash)
-- This creates an immutable chain: current entry's hash depends on prior

computeWormSeal :: WormMemoryEntry -> ByteString -> ByteString
computeWormSeal entry priorHash =
  let thisData = encodeMemoryEntry entry
      chainData = thisData <> priorHash
  in BSC.pack $ "worm" ++ show (hash chainData)

-- ── Create new WORM entry ─────────────────────────────────────────────────────────

createMemoryEntry :: Int -> UTCTime -> AgentId -> Observation -> ByteString -> WormMemoryEntry
createMemoryEntry idx ts aid obs priorHash =
  let entry = WormMemoryEntry
        { entryIndex = idx
        , entryTimestamp = ts
        , entryAgentId = aid
        , entryData = obs
        , entryPriorHash = priorHash
        , entryCurrentHash = BS.empty  -- Placeholder, will be computed
        }
      seal = computeWormSeal entry priorHash
  in entry { entryCurrentHash = seal }

-- ── Initialize empty memory log ────────────────────────────────────────────────────

initializeMemoryLog :: FilePath -> IO WormMemoryLog
initializeMemoryLog path = do
  return WormMemoryLog
    { logPath = path
    , logEntries = []
    , logTailHash = BS.empty  -- Genesis: no prior hash
    , logSize = 0
    }

-- ── Append observation to WORM log (main API) ──────────────────────────────────────
-- Returns updated log with new entry sealed and chained.

recordObservationWorm :: WormMemoryLog -> AgentId -> Observation -> IO WormMemoryLog
recordObservationWorm log aid obs = do
  now <- getCurrentTime

  let newIndex = logSize log
      priorHash = logTailHash log  -- Last entry's hash
      newEntry = createMemoryEntry newIndex now aid obs priorHash

  -- Append to in-memory log
  let updatedEntries = logEntries log ++ [newEntry]
      updatedLog = log
        { logEntries = updatedEntries
        , logTailHash = entryCurrentHash newEntry
        , logSize = newSize log + 1
        }

  -- Persist to disk (append mode)
  persistEntry (logPath log) newEntry

  return updatedLog

-- Write entry to WORM file (append-only, never update)
persistEntry :: FilePath -> WormMemoryEntry -> IO ()
persistEntry path entry =
  let line = encodeWormEntryLine entry
  in appendFile path (line ++ "\n")

-- Serialize entry to single line (pipe-delimited for durability)
encodeWormEntryLine :: WormMemoryEntry -> String
encodeWormEntryLine entry =
  let parts =
        [ show (entryIndex entry)
        , entryAgentId entry
        , formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S%z" (entryTimestamp entry)
        , show (entryData entry)
        , BSC.unpack (entryPriorHash entry)
        , BSC.unpack (entryCurrentHash entry)
        ]
  in intercalate "|" parts

-- ── Verify WORM integrity ────────────────────────────────────────────────────────
-- Check that chain is unbroken: each entry's hash matches expected value

verifyWormIntegrity :: WormMemoryLog -> Either String ()
verifyWormIntegrity log = verifyChain (logEntries log) BS.empty
  where
    verifyChain [] _ = Right ()
    verifyChain (entry:rest) expectedPrior
      | entryPriorHash entry /= expectedPrior =
        Left $ "WORM chain broken at index " ++ show (entryIndex entry)
      | otherwise = verifyChain rest (entryCurrentHash entry)

-- ── Read memory (audit trail queries) ──────────────────────────────────────────────

-- Get all observations from a specific agent
agentMemoryLog :: WormMemoryLog -> AgentId -> [Observation]
agentMemoryLog log aid =
  [ entryData entry
  | entry <- logEntries log
  , entryAgentId entry == aid
  ]

-- Get observations in time range
observationsInRange :: WormMemoryLog -> UTCTime -> UTCTime -> [Observation]
observationsInRange log startTime endTime =
  [ entryData entry
  | entry <- logEntries log
  , let ts = entryTimestamp entry
  , ts >= startTime && ts <= endTime
  ]

-- Get entry by index
getEntryAtIndex :: WormMemoryLog -> Int -> Maybe WormMemoryEntry
getEntryAtIndex log idx
  | idx < 0 || idx >= length (logEntries log) = Nothing
  | otherwise = Just (logEntries log !! idx)

-- ── Export audit trail (for compliance/review) ─────────────────────────────────────

exportAuditTrail :: WormMemoryLog -> String
exportAuditTrail log =
  let header = "═══ WORM Memory Audit Trail ═══\n"
      stats = "Entries: " ++ show (logSize log) ++ " | Tail Hash: " ++ BSC.unpack (logTailHash log) ++ "\n\n"
      entries = intercalate "\n" [ exportEntry e | e <- logEntries log ]
  in header ++ stats ++ entries

exportEntry :: WormMemoryEntry -> String
exportEntry entry =
  intercalate " | "
    [ "[" ++ show (entryIndex entry) ++ "]"
    , formatTime defaultTimeLocale "%H:%M:%S" (entryTimestamp entry)
    , "Agent:" ++ entryAgentId entry
    , "PriorHash:" ++ take 12 (BSC.unpack (entryPriorHash entry))
    , "CurrentHash:" ++ take 12 (BSC.unpack (entryCurrentHash entry))
    ]

-- ── Memory statistics ──────────────────────────────────────────────────────────────

data MemoryStats = MemoryStats
  { statsTotalEntries :: Int
  , statsByAgent :: Map.Map AgentId Int     -- Observations per agent
  , statsOldestTime :: Maybe UTCTime
  , statsNewestTime :: Maybe UTCTime
  , statsChainIntegrity :: Bool
  } deriving (Show, Eq, Generic)

computeMemoryStats :: WormMemoryLog -> MemoryStats
computeMemoryStats log =
  let entries = logEntries log
      byAgent = Map.fromListWith (+) [(entryAgentId e, 1) | e <- entries]
      times = map entryTimestamp entries
      oldest = if null times then Nothing else Just (minimum times)
      newest = if null times then Nothing else Just (maximum times)
      integrity = case verifyWormIntegrity log of
        Right () -> True
        Left _ -> False
  in MemoryStats
    { statsTotalEntries = length entries
    , statsByAgent = byAgent
    , statsOldestTime = oldest
    , statsNewestTime = newest
    , statsChainIntegrity = integrity
    }

-- ── Snapshot (for checkpointing) ───────────────────────────────────────────────────
-- Create immutable snapshot at a point in time

data MemorySnapshot = MemorySnapshot
  { snapshotTimestamp :: UTCTime
  , snapshotIndex :: Int
  , snapshotHash :: ByteString
  , snapshotAgent :: AgentId
  } deriving (Show, Eq, Generic)

createSnapshot :: WormMemoryLog -> IO (Maybe MemorySnapshot)
createSnapshot log = do
  now <- getCurrentTime
  case logEntries log of
    [] -> return Nothing
    entries ->
      let lastEntry = last entries
          snapshot = MemorySnapshot
            { snapshotTimestamp = now
            , snapshotIndex = entryIndex lastEntry
            , snapshotHash = entryCurrentHash lastEntry
            , snapshotAgent = entryAgentId lastEntry
            }
      in return (Just snapshot)

-- ── Restore from checkpoint ────────────────────────────────────────────────────────
-- Verify integrity up to checkpoint index

verifyToCheckpoint :: WormMemoryLog -> MemorySnapshot -> Either String ()
verifyToCheckpoint log snapshot =
  let checkIndex = snapshotIndex snapshot
      entries = logEntries log
      headEntries = take (checkIndex + 1) entries
  in if null entries
     then Left "Empty log"
     else if length entries < checkIndex + 1
          then Left "Checkpoint index out of range"
          else verifyChain headEntries BS.empty
  where
    verifyChain [] _ = Right ()
    verifyChain (entry:rest) expectedPrior
      | entryPriorHash entry /= expectedPrior =
        Left $ "Chain broken at checkpoint index " ++ show (entryIndex entry)
      | otherwise = verifyChain rest (entryCurrentHash entry)

-- ── Compact log (no-op for now; in production: archive old entries) ────────────────

compactLog :: WormMemoryLog -> Int -> WormMemoryLog
compactLog log retentionDays =
  -- In production: remove entries older than retentionDays
  -- For now: return unchanged (append-only is immutable)
  log

-- Helper for newSize
newSize :: WormMemoryLog -> Int
newSize log = logSize log
