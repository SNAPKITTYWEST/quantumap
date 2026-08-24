{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}

module ConsensusTypes where

import qualified Data.Map as Map
import Data.Map (Map)
import GHC.Generics (Generic)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Hashable
import Data.List (sortBy, groupBy)
import Data.Ord (comparing)

-- ─────────────────────────────────────────────────────────────────────────────
-- Core Types: Agent + Observation + Vote
-- ─────────────────────────────────────────────────────────────────────────────

-- | Unique agent identifier
newtype AgentId = AgentId Int
  deriving (Eq, Ord, Show, Generic)

instance Hashable AgentId

-- | Unique observation identifier
newtype ObservationId = ObservationId Int
  deriving (Eq, Ord, Show, Generic)

instance Hashable ObservationId

-- | Unique region identifier
newtype RegionId = RegionId Int
  deriving (Eq, Ord, Show, Generic)

instance Hashable RegionId

-- | 3D vector for positions
data Vector = Vector { vx :: Double, vy :: Double, vz :: Double }
  deriving (Eq, Show, Generic)

instance Hashable Vector

-- | Region type classification (from manifold exploration)
data RegionType = RegionType
  { rtName :: String
  , rtDensity :: Double
  , rtCurvature :: Double
  , rtAnomalyLevel :: Double
  } deriving (Eq, Show, Generic, Ord)

instance Hashable RegionType

-- | Measurement bundle (timestamp + readings)
data Measurement = Measurement
  { measTimestamp :: Int
  , measValues :: Map String Double
  } deriving (Eq, Show, Generic)

-- | Observation from a single agent (immutable, observable-only)
data Observation = Observation
  { obsId :: ObservationId
  , agentId :: AgentId
  , timestamp :: Int
  , coordinates :: Vector
  , measurements :: Map String Double    -- e.g., "density" -> 0.523
  , confidence :: Double                 -- [0, 1] agent's self-confidence
  , regionType :: Maybe RegionType       -- classified region
  , wormSealed :: Bool                   -- WORM seal status
  , sealRound :: Maybe Int               -- round number when sealed
  } deriving (Eq, Show, Generic)

-- | Vote from one agent on another's observation
data Vote = Vote
  { voterId :: AgentId
  , votedObsId :: ObservationId
  , agreement :: Double                  -- [-1, 1]: -1 disagree, 0 uncertain, +1 agree
  , voteRound :: Int
  , voteTimestamp :: Int
  } deriving (Eq, Show, Generic)

-- | Voting round metadata
data VoteRound = VoteRound
  { roundNum :: Int
  , roundTimestamp :: Int
  , roundVotes :: [Vote]
  , roundObservations :: [Observation]
  } deriving (Eq, Show, Generic)

-- | Anomaly detection record
data Anomaly = Anomaly
  { anomalyId :: Int
  , anomalyLocation :: Vector
  , anomalySeverity :: Double            -- [0, 1]
  , anomalyRound :: Int
  , anomalyAgents :: [AgentId]           -- which agents observed it
  , anomalyConfidence :: Double          -- consensus confidence [0, 1]
  } deriving (Eq, Show, Generic)

-- | Conflict detection (two agents disagree on same measurement)
data Conflict = Conflict
  { conflictObsId :: ObservationId
  , conflictRegionId :: RegionId
  , conflictAgents :: [AgentId]
  , conflictMeasureDiff :: Double        -- magnitude of disagreement
  , conflictResolved :: Bool
  } deriving (Eq, Show, Generic)

-- | Shared world model (consensus result)
data WorldModel = WorldModel
  { regionTypes :: Map RegionId RegionType
  , agentPositions :: Map AgentId Vector
  , anomalies :: [Anomaly]
  , frontierRegions :: [RegionId]
  , modelConfidence :: Double            -- collective confidence [0, 1]
  , modelGeneration :: Int               -- which round produced this model
  } deriving (Eq, Show, Generic)

-- | Complete consensus state (accumulates over rounds)
data ConsensusState = ConsensusState
  { observations :: [Observation]
  , votes :: [Vote]
  , voteRounds :: [VoteRound]
  , worldModel :: WorldModel
  , confidence :: Double                 -- global consensus confidence [0, 1]
  , conflicts :: [Conflict]
  , wormSealLog :: [SealRecord]          -- WORM-sealed audit trail
  , generation :: Int                    -- consensus generation number
  } deriving (Eq, Show, Generic)

-- | WORM-sealed audit record
data SealRecord = SealRecord
  { sealRound :: Int
  , sealTimestamp :: Int
  , sealedObsCount :: Int
  , sealedVoteCount :: Int
  , sealHash :: ByteString               -- Blake3 hash of sealed data
  , sealAgents :: [AgentId]              -- agents participating in round
  } deriving (Eq, Show, Generic)

-- ─────────────────────────────────────────────────────────────────────────────
-- Initial State Constructors
-- ─────────────────────────────────────────────────────────────────────────────

-- | Create empty world model
emptyWorldModel :: WorldModel
emptyWorldModel = WorldModel
  { regionTypes = Map.empty
  , agentPositions = Map.empty
  , anomalies = []
  , frontierRegions = []
  , modelConfidence = 0.0
  , modelGeneration = 0
  }

-- | Create empty consensus state
emptyConsensusState :: ConsensusState
emptyConsensusState = ConsensusState
  { observations = []
  , votes = []
  , voteRounds = []
  , worldModel = emptyWorldModel
  , confidence = 0.0
  , conflicts = []
  , wormSealLog = []
  , generation = 0
  }

-- | Create observation from agent reading
makeObservation :: ObservationId -> AgentId -> Int -> Vector
                -> Map String Double -> Double -> Maybe RegionType
                -> Observation
makeObservation oid aid ts pos meas conf regType = Observation
  { obsId = oid
  , agentId = aid
  , timestamp = ts
  , coordinates = pos
  , measurements = meas
  , confidence = max 0.0 (min 1.0 conf)
  , regionType = regType
  , wormSealed = False
  , sealRound = Nothing
  }

-- | Create vote
makeVote :: AgentId -> ObservationId -> Double -> Int -> Int -> Vote
makeVote voter obsId agrmt round ts = Vote
  { voterId = voter
  , votedObsId = obsId
  , agreement = max (-1.0) (min 1.0 agrmt)
  , voteRound = round
  , voteTimestamp = ts
  }

-- ─────────────────────────────────────────────────────────────────────────────
-- Utility Functions
-- ─────────────────────────────────────────────────────────────────────────────

-- | Calculate Euclidean distance between vectors
vectorDistance :: Vector -> Vector -> Double
vectorDistance v1 v2 = sqrt ((vx v1 - vx v2)^2 + (vy v1 - vy v2)^2 + (vz v1 - vz v2)^2)

-- | Average a list of doubles
averageDouble :: [Double] -> Double
averageDouble [] = 0.0
averageDouble xs = sum xs / fromIntegral (length xs)

-- | Filter votes for a specific observation
votesForObservation :: [Vote] -> ObservationId -> [Vote]
votesForObservation vs obsId = filter (\v -> votedObsId v == obsId) vs

-- | Filter observations by agent
observationsByAgent :: [Observation] -> AgentId -> [Observation]
observationsByAgent obs aid = filter (\o -> agentId o == aid) obs

-- | Calculate consensus score for observation (average agreement)
consensusScore :: [Vote] -> Double
consensusScore [] = 0.0
consensusScore vs = averageDouble (map agreement vs)

-- | Check if observation has consensus (66%+ agreement)
hasConsensus :: [Vote] -> Bool
hasConsensus vs
  | null vs = False
  | otherwise = let score = consensusScore vs
                    positiveVotes = fromIntegral (length (filter (\v -> agreement v > 0.5) vs)) :: Double
                    ratioVotes = positiveVotes / fromIntegral (length vs)
                in score > 0.33 && ratioVotes >= 0.66

-- | Measurement difference metric (normalized L2)
measurementDifference :: Map String Double -> Map String Double -> Double
measurementDifference m1 m2 =
  let allKeys = Map.keys m1 ++ Map.keys m2
      diffs = map (\k -> let v1 = Map.findWithDefault 0.0 k m1
                             v2 = Map.findWithDefault 0.0 k m2
                         in abs (v1 - v2)) allKeys
  in if null diffs then 0.0 else averageDouble diffs

-- | Group observations by region
groupByRegion :: [Observation] -> Map RegionId [Observation]
groupByRegion obs =
  let grouped = groupBy (\o1 o2 -> regionType o1 == regionType o2)
                        (sortBy (comparing regionType) obs)
  in Map.fromList [(RegionId i, g) | (i, g) <- zip [0..] grouped]

-- | Get all agents from observations and votes
extractAgentIds :: ConsensusState -> [AgentId]
extractAgentIds state =
  let fromObs = map agentId (observations state)
      fromVotes = map voterId (votes state)
  in nub (fromObs ++ fromVotes)
  where
    nub [] = []
    nub (x:xs) = x : nub (filter (/= x) xs)
