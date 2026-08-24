-- ═══════════════════════════════════════════════════════════════════════════════
-- SpacetimeAgent.hs — Agent Position & Decision Framework
-- bridges/haskell/SpacetimeAgent.hs
--
-- PHASE 7 AGENT EXPLORATION. OBSERVABLE-ONLY. WORM-SEALED HISTORY.
--
-- Agents operate in simulated manifolds with:
--   - Position/state representation in spacetime coordinates
--   - Memory of previous observations (WORM-sealed)
--   - Goal system (Explore, Map, Detect, Collaborate)
--   - Frame detection (Unknown, Gravity, Relativity, Quantum, Wormhole, Horizon)
--   - Resource tracking (movement, observation, message budgets)
--
-- Decision policy frames detection for "what kind of region am I in?"
-- All observations are immutable; agents measure, never mutate reality.
--
-- ═══════════════════════════════════════════════════════════════════════════════

{-# LANGUAGE DeriveGeneric #-}

module SpacetimeAgent where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.List (intercalate)
import Data.Maybe (fromMaybe, catMaybes)
import qualified Data.Map.Strict as Map
import GHC.Generics (Generic)
import Data.Hashable (hash)

-- ── Observable Spacetime Frame ────────────────────────────────────────────────────
-- Agents detect which frame they are observing from.

data Frame
  = Unknown             -- No frame detected yet
  | Gravity             -- Curvature/gravitational effects
  | Relativity          -- Time scaling/relative effects
  | Quantum             -- Probabilistic/superposition state
  | Wormhole            -- Multiple paths / topology shortcuts
  | Horizon             -- Event boundary / information barrier
  deriving (Show, Eq, Ord, Generic)

-- ── Agent Goal Types ──────────────────────────────────────────────────────────────

data Goal
  = Explore Subgoal
  | Map RegionOfInterest
  | Detect AnomalyType
  | Collaborate AgentId
  deriving (Show, Eq, Generic)

data Subgoal
  = ExpandBoundary
  | SampleRegion
  | TraceTopology
  | FindConnections
  deriving (Show, Eq, Generic)

data RegionOfInterest
  = LocalRegion Double  -- Radius of interest
  | SpecificCoordinates [Double]
  deriving (Show, Eq, Generic)

data AnomalyType
  = CurvatureSpike
  | TemporalAnomaly
  | SuperpositionCollapse
  | TopologyChange
  deriving (Show, Eq, Generic)

type AgentId = String

-- ── Resource Budget (enforced, non-negative) ──────────────────────────────────────

data ResourceBudget = ResourceBudget
  { movementBudget :: Int        -- Steps agent can move
  , observationBudget :: Int     -- Observations it can record
  , messageBudget :: Int         -- Messages it can send to swarm
  , currentUsage :: ResourceUsage
  } deriving (Show, Eq, Generic)

data ResourceUsage = ResourceUsage
  { movementUsed :: Int
  , observationUsed :: Int
  , messageUsed :: Int
  } deriving (Show, Eq, Generic)

-- Resource checking predicates
canMove :: ResourceBudget -> Bool
canMove b = movementUsed (currentUsage b) < movementBudget b

canObserve :: ResourceBudget -> Bool
canObserve b = observationUsed (currentUsage b) < observationBudget b

canMessage :: ResourceBudget -> Bool
canMessage b = messageUsed (currentUsage b) < messageBudget b

-- Remaining budget (observable, non-negative)
remainingMovement :: ResourceBudget -> Int
remainingMovement b = max 0 (movementBudget b - movementUsed (currentUsage b))

remainingObservation :: ResourceBudget -> Int
remainingObservation b = max 0 (observationBudget b - observationUsed (currentUsage b))

remainingMessage :: ResourceBudget -> Int
remainingMessage b = max 0 (messageBudget b - messageUsed (currentUsage b))

-- ── Observation (immutable, WORM-sealed) ──────────────────────────────────────────

data Observation = Observation
  { obsTimestamp :: Int
  , obsPosition :: [Double]
  , obsMeasurements :: Map.Map String Double
  , obsFrameDetected :: Frame
  , obsHash :: ByteString         -- WORM hash: blake3(thisObs ++ priorHash)
  } deriving (Show, Eq, Generic)

-- Encode observation to ByteString for hashing
encodeObservation :: Observation -> ByteString
encodeObservation obs =
  let coordStr = intercalate "," (map show (obsPosition obs))
      measStr = intercalate ";" (map (\(k,v) -> k ++ "=" ++ show v) (Map.toList (obsMeasurements obs)))
      frameStr = show (obsFrameDetected obs)
      parts = [show (obsTimestamp obs), coordStr, measStr, frameStr]
  in BSC.pack (intercalate "|" parts)

-- Simple hash for WORM chaining (in production: blake3)
simpleHash :: ByteString -> ByteString
simpleHash bs = BSC.pack $ "h" ++ show (hash bs)

-- ── Agent Position & State ────────────────────────────────────────────────────────

data AgentPosition = AgentPosition
  { coordinates :: [Double]       -- n-dimensional position
  , observerFrame :: Frame         -- Current frame
  , lastObservation :: Maybe Observation
  , memoryLog :: [Observation]     -- WORM-sealed history
  } deriving (Show, Eq, Generic)

-- ── Agent Decision State (at decision point) ──────────────────────────────────────

data AgentDecision = AgentDecision
  { agentId :: AgentId
  , agentGoal :: Goal
  , resourceBudget :: ResourceBudget
  , confidenceLevel :: Double      -- 0-1 confidence in current frame
  , explorationPath :: [AgentPosition]
  , decisionCount :: Int
  } deriving (Show, Eq, Generic)

-- ── Actions agents can take ───────────────────────────────────────────────────────

data Action
  = MoveRandom Int                 -- Random walk, steps limit
  | MoveAlongGradient [Double]     -- Move in direction
  | RecordObservation [Double]     -- Take measurement at position
  | SampleSuperposition            -- Probe quantum region
  | SendMessageToSwarm AgentId String  -- Send message to peer
  | Wait                           -- No action (conserve resources)
  deriving (Show, Eq, Generic)

-- ── Frame Detection (Ahmad's reframing logic) ─────────────────────────────────────
-- Given observations, infer which frame we're in.

detectFrame :: Observation -> Frame
detectFrame obs
  | curvatureDetected obs = Gravity
  | timeScalingDetected obs = Relativity
  | probabilisticState obs = Quantum
  | alternatePathsDetected obs = Wormhole
  | eventHorizonNear obs = Horizon
  | otherwise = Unknown

-- Helper predicates for frame detection

curvatureDetected :: Observation -> Bool
curvatureDetected obs =
  case Map.lookup "curvature" (obsMeasurements obs) of
    Just v -> v > 0.1
    Nothing -> False

timeScalingDetected :: Observation -> Bool
timeScalingDetected obs =
  case Map.lookup "time_scale" (obsMeasurements obs) of
    Just v -> v /= 1.0
    Nothing -> False

probabilisticState :: Observation -> Bool
probabilisticState obs =
  case Map.lookup "entropy" (obsMeasurements obs) of
    Just v -> v > 0.3
    Nothing -> False

alternatePathsDetected :: Observation -> Bool
alternatePathsDetected obs =
  case Map.lookup "paths" (obsMeasurements obs) of
    Just v -> v > 1.0
    Nothing -> False

eventHorizonNear :: Observation -> Bool
eventHorizonNear obs =
  case Map.lookup "horizon_distance" (obsMeasurements obs) of
    Just v -> v < 1.0
    Nothing -> False

-- ── Decision Policy (frame + goal → action) ───────────────────────────────────────
-- Observable-only: agents read state, never mutate.

decideNextAction :: AgentDecision -> Observation -> Maybe Action
decideNextAction decision obs
  | not (canMove (resourceBudget decision)) && not (canObserve (resourceBudget decision)) = Just Wait
  | otherwise = case (agentGoal decision, detectFrame obs) of
    -- Explore: expand knowledge of manifold
    (Explore ExpandBoundary, Unknown) | canMove (resourceBudget decision) ->
      Just (MoveRandom (remainingMovement (resourceBudget decision)))
    (Explore ExpandBoundary, Gravity) | canMove (resourceBudget decision) ->
      Just (MoveAlongGradient (computeGradient obs))
    (Explore TraceTopology, Wormhole) | canObserve (resourceBudget decision) ->
      Just (RecordObservation (obsPosition obs))

    -- Map: record detailed topology
    (Map _, _) | canObserve (resourceBudget decision) ->
      Just (RecordObservation (obsPosition obs))

    -- Detect: sample for anomalies
    (Detect _, Quantum) | canObserve (resourceBudget decision) ->
      Just SampleSuperposition
    (Detect _, Horizon) | canObserve (resourceBudget decision) ->
      Just (RecordObservation (obsPosition obs))

    -- Collaborate: advertise to swarm
    (Collaborate peerId, _) | canMessage (resourceBudget decision) ->
      Just (SendMessageToSwarm peerId ("position:" ++ show (obsPosition obs)))

    -- Default: wait
    _ -> Just Wait

-- Compute gradient direction from measurements (stub)
computeGradient :: Observation -> [Double]
computeGradient obs =
  let curvature = fromMaybe 0.0 (Map.lookup "curvature" (obsMeasurements obs))
  in replicate (length (obsPosition obs)) (curvature * 0.01)

-- ── Confidence update (based on consistent frame) ─────────────────────────────────

updateConfidence :: AgentPosition -> Observation -> Double
updateConfidence pos obs =
  let detectedFrame = detectFrame obs
      lastFrame = observerFrame pos
      matches = detectedFrame == lastFrame
      increment = if matches then 0.1 else -0.05
  in min 1.0 (max 0.0 (0.5 + increment))  -- Bounded [0,1]

-- ── Goal Updates (based on observations) ───────────────────────────────────────────

updateGoal :: Agent -> Observation -> Goal
updateGoal agent obs =
  let frame = detectFrame obs
      oldGoal = agentGoal (decision agent)
  in case frame of
    Horizon -> Detect AnomalyType.Anomaly    -- Near horizon: detect anomalies
    Wormhole -> Explore Connections          -- Wormhole: explore shortcuts
    Quantum -> Detect AnomalyType.Superposition  -- Quantum: sample states
    _ -> Map (LocalRegion 1.0)                -- Default: map region

-- Workaround for pattern matching (AnomalyType constructor)
-- Note: adjust based on actual AnomalyType variants
-- updateGoal uses Map as safe default for most frames

-- ── Full Agent State ──────────────────────────────────────────────────────────────

data Agent = Agent
  { agentIdentity :: AgentId
  , position :: AgentPosition
  , decision :: AgentDecision
  , createdAt :: Int                -- Timestamp
  , observationCount :: Int
  } deriving (Show, Eq, Generic)

-- ── Create new agent at position ───────────────────────────────────────────────────

createAgent :: AgentId -> [Double] -> Int -> Agent
createAgent aid coords timestamp =
  Agent
    { agentIdentity = aid
    , position = AgentPosition
        { coordinates = coords
        , observerFrame = Unknown
        , lastObservation = Nothing
        , memoryLog = []
        }
    , decision = AgentDecision
        { agentId = aid
        , agentGoal = Explore SampleRegion
        , resourceBudget = ResourceBudget
            { movementBudget = 100
            , observationBudget = 50
            , messageBudget = 20
            , currentUsage = ResourceUsage 0 0 0
            }
        , confidenceLevel = 0.0
        , explorationPath = []
        , decisionCount = 0
        }
    , createdAt = timestamp
    , observationCount = 0
    }

-- ── Record observation (immutable append) ──────────────────────────────────────────

recordObservation :: Agent -> Observation -> Agent
recordObservation agent obs =
  let priorHash = case lastObservation (position agent) of
        Just lastObs -> obsHash lastObs
        Nothing -> BS.empty
      newObs = obs { obsHash = simpleHash (encodeObservation obs <> priorHash) }
      newPos = (position agent)
        { lastObservation = Just newObs
        , memoryLog = memoryLog (position agent) ++ [newObs]
        }
      newBudget = (resourceBudget (decision agent))
        { currentUsage = let u = currentUsage (resourceBudget (decision agent))
                         in u { observationUsed = observationUsed u + 1 }
        }
      newDecision = (decision agent)
        { resourceBudget = newBudget
        , decisionCount = decisionCount (decision agent) + 1
        }
  in agent
    { position = newPos
    , decision = newDecision
    , observationCount = observationCount agent + 1
    }

-- ── Move agent (update position, consume resource) ────────────────────────────────

moveAgent :: Agent -> [Double] -> Agent
moveAgent agent newCoords
  | not (canMove (resourceBudget (decision agent))) = agent  -- No budget: no move
  | otherwise =
    let newPos = (position agent) { coordinates = newCoords }
        newBudget = (resourceBudget (decision agent))
          { currentUsage = let u = currentUsage (resourceBudget (decision agent))
                           in u { movementUsed = movementUsed u + 1 }
          }
        newDecision = (decision agent)
          { resourceBudget = newBudget
          , explorationPath = explorationPath (decision agent) ++ [position agent]
          , decisionCount = decisionCount (decision agent) + 1
          }
    in agent
      { position = newPos
      , decision = newDecision
      }

-- ── Send message (consume resource) ────────────────────────────────────────────────

sendMessage :: Agent -> AgentId -> String -> Agent
sendMessage agent targetId msg
  | not (canMessage (resourceBudget (decision agent))) = agent  -- No budget: no message
  | otherwise =
    let newBudget = (resourceBudget (decision agent))
          { currentUsage = let u = currentUsage (resourceBudget (decision agent))
                           in u { messageUsed = messageUsed u + 1 }
          }
        newDecision = (decision agent)
          { resourceBudget = newBudget
          , decisionCount = decisionCount (decision agent) + 1
          }
    in agent
      { decision = newDecision
      }

-- ── Agent status summary (for logging) ────────────────────────────────────────────

agentStatus :: Agent -> String
agentStatus agent =
  let pos = position agent
      dec = decision agent
      budget = resourceBudget dec
      usage = currentUsage budget
      movedCells = explorationPath dec
  in intercalate " | "
    [ "Agent:" ++ agentIdentity agent
    , "Pos:" ++ show (coordinates pos)
    , "Frame:" ++ show (observerFrame pos)
    , "Goal:" ++ show (agentGoal dec)
    , "Confidence:" ++ printf "%.2f" (confidenceLevel dec)
    , "Movement:" ++ show (movementUsed usage) ++ "/" ++ show (movementBudget budget)
    , "Observations:" ++ show (observationUsed usage) ++ "/" ++ show (observationBudget budget)
    , "Messages:" ++ show (messageUsed usage) ++ "/" ++ show (messageBudget budget)
    , "MemorySize:" ++ show (length (memoryLog pos))
    ]

-- Printf-like helper for formatting
printf :: String -> Double -> String
printf fmt val = show val  -- Simplified; use Text.Printf in production
