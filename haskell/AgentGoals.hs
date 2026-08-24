-- ═══════════════════════════════════════════════════════════════════════════════
-- AgentGoals.hs — Goal System & Adaptation
-- bridges/haskell/AgentGoals.hs
--
-- PHASE 7 AGENT GOALS. ADAPTIVE. FRAME-AWARE.
--
-- Goals are the "why" behind agent actions.
-- Agents adjust goals based on observations and detected frame.
--
-- Frame → Goal mapping:
--   Gravity → Map (record gravitational structure)
--   Relativity → Detect (measure time effects)
--   Quantum → Detect (sample superposition)
--   Wormhole → Explore (find connections)
--   Horizon → Detect (anomalies near boundaries)
--   Unknown → Explore (gather data)
--
-- Goals are observable: agents commit to them, but can adapt.
--
-- ═══════════════════════════════════════════════════════════════════════════════

{-# LANGUAGE DeriveGeneric #-}

module AgentGoals where

import Data.List (intercalate)
import GHC.Generics (Generic)
import qualified Data.Map.Strict as Map
import SpacetimeAgent
  ( Agent(..), Observation(..), Frame(..), Goal(..), Subgoal(..)
  , AgentId, RegionOfInterest(..), AnomalyType(..)
  )

-- ── Goal Satisfaction Metric ───────────────────────────────────────────────────────
-- Tracks progress toward goal

data GoalProgress = GoalProgress
  { progressGoalId :: Int              -- Which goal instance
  , progressType :: GoalType           -- What kind of goal
  , progressStatus :: ProgressStatus
  , progressMetric :: Double           -- 0-1 completion estimate
  , progressObservations :: Int        -- How many obs contributed
  , progressUpdatedAt :: Int           -- Timestamp
  } deriving (Show, Eq, Generic)

data GoalType
  = GoalExplore
  | GoalMap
  | GoalDetect
  | GoalCollaborate
  deriving (Show, Eq, Generic)

data ProgressStatus
  = Active
  | Paused
  | Completed
  | Failed
  deriving (Show, Eq, Generic)

-- ── Frame-based goal selection ─────────────────────────────────────────────────────
-- Given current frame, what should agent prioritize?

selectGoalForFrame :: Frame -> Observation -> Goal
selectGoalForFrame frame obs =
  case frame of
    Gravity ->
      Map (LocalRegion 2.0)           -- Map gravitational region

    Relativity ->
      Detect TemporalAnomaly          -- Detect time-based anomalies

    Quantum ->
      Detect SuperpositionCollapse    -- Sample quantum collapse

    Wormhole ->
      Explore FindConnections         -- Find topology shortcuts

    Horizon ->
      Detect CurvatureSpike           -- Monitor event horizon

    Unknown ->
      Explore SampleRegion            -- Gather initial data

-- ── Goal inheritance (agents learn from peers) ─────────────────────────────────────
-- If another agent succeeded at a goal, inherit it

inheritGoal :: Agent -> AgentId -> Goal -> Agent
inheritGoal agent sourceAgent newGoal =
  let oldDecision = decision agent
      newDecision = oldDecision { agentGoal = newGoal }
  in agent { decision = newDecision }

-- ── Goal termination (agent completed or gave up) ───────────────────────────────────

data GoalTermination
  = SuccessfulCompletion
  | BudgetExhausted
  | NoProgressAfterN Int
  | DetectedImpossible
  deriving (Show, Eq, Generic)

-- Check if goal should be abandoned
shouldAbandonGoal :: Agent -> GoalProgress -> Bool
shouldAbandonGoal agent progress =
  let budget = resourceBudget (decision agent)
      usage = currentUsage budget
      -- Abandon if: no resources left, or no progress in 10 steps
      noBudget = movementUsed usage >= movementBudget budget
                && observationUsed usage >= observationBudget budget
      noProgress = progressObservations progress == 0
  in noBudget || noProgress

-- ── Goal transition (when to switch goals) ────────────────────────────────────────

data GoalTransition = GoalTransition
  { fromGoal :: Goal
  , toGoal :: Goal
  , reason :: TransitionReason
  , decidedAt :: Int                  -- Step number
  } deriving (Show, Eq, Generic)

data TransitionReason
  = FrameChange                       -- Detected new frame
  | GoalCompleted                     -- Goal satisfied
  | ResourceLimited                   -- Budget pressure
  | PeerSuggestion AgentId            -- Another agent recommended
  | OptimalitySwitch                  -- Found better goal
  deriving (Show, Eq, Generic)

-- Decide if goal transition is warranted
shouldTransitionGoal :: Agent -> Observation -> GoalProgress -> Maybe TransitionReason
shouldTransitionGoal agent obs progress =
  let currentFrame = observerFrame (position agent)
      selectedFrame = detectFrame obs
      -- Transition if frame changed significantly
      frameChanged = currentFrame /= selectedFrame
      -- Transition if goal is stuck
      isStuck = progressMetric progress < 0.1 && progressObservations progress > 20
      -- Transition if budget low
      budgetLow = remainingMovement (resourceBudget (decision agent)) < 5
  in case () of
    _ | frameChanged -> Just FrameChange
    _ | isStuck -> Just OptimalitySwitch
    _ | budgetLow -> Just ResourceLimited
    _ -> Nothing

-- Helper: detectFrame for AgentGoals module
detectFrame :: Observation -> Frame
detectFrame obs
  | curvatureDetected obs = Gravity
  | timeScalingDetected obs = Relativity
  | probabilisticState obs = Quantum
  | alternatePathsDetected obs = Wormhole
  | eventHorizonNear obs = Horizon
  | otherwise = Unknown

-- Helper predicates
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

-- Helper: remainingMovement from ResourceBudget
remainingMovement :: ResourceBudget -> Int
remainingMovement b = max 0 (movementBudget b - movementUsed (currentUsage b))

-- ── Goal coalignment (multi-agent goal networks) ────────────────────────────────────
-- Track which agents are pursuing complementary goals

data GoalCoalignment = GoalCoalignment
  { agentsAligned :: [AgentId]
  , alignedGoal :: Goal
  , synergyValue :: Double            -- Benefit of cooperation (0-1)
  , communicationBudget :: Int        -- Messages to coordinate
  } deriving (Show, Eq, Generic)

-- Compute synergy when agents share a goal
computeSynergy :: [Agent] -> Goal -> Double
computeSynergy agents sharedGoal =
  let matchCount = length $ filter (\a -> agentGoal (decision a) == sharedGoal) agents
      coordCost = if matchCount > 1 then 0.1 else 0.0
  in max 0.0 (0.5 + fromIntegral matchCount * 0.2 - coordCost)

-- ── Goal history (for learning/debugging) ──────────────────────────────────────────

data GoalHistory = GoalHistory
  { historyAgentId :: AgentId
  , historyGoals :: [(Int, Goal)]     -- (timestamp, goal)
  , historyTransitions :: [GoalTransition]
  , historySuccess :: Int             -- Goals completed
  , historyAbandoned :: Int           -- Goals abandoned
  } deriving (Show, Eq, Generic)

-- Log goal adoption
recordGoalAdoption :: GoalHistory -> Int -> Goal -> GoalHistory
recordGoalAdoption hist timestamp goal =
  hist { historyGoals = historyGoals hist ++ [(timestamp, goal)] }

-- Log goal completion
recordGoalCompletion :: GoalHistory -> GoalHistory
recordGoalCompletion hist = hist { historySuccess = historySuccess hist + 1 }

-- Log goal abandonment
recordGoalAbandonment :: GoalHistory -> GoalHistory
recordGoalAbandonment hist = hist { historyAbandoned = historyAbandoned hist + 1 }

-- ── Goal announcement to swarm ─────────────────────────────────────────────────────
-- When an agent adopts a goal, it broadcasts to peers

goalAnnouncement :: Agent -> String
goalAnnouncement agent =
  let aid = agentIdentity agent
      goal = agentGoal (decision agent)
      conf = confidenceLevel (decision agent)
      pos = coordinates (position agent)
  in intercalate " | "
    [ "GOAL_ANNOUNCE:" ++ aid
    , "goal=" ++ show goal
    , "confidence=" ++ show conf
    , "position=" ++ show pos
    ]

-- ── Goal satisfaction predicates ───────────────────────────────────────────────────

isGoalSatisfied :: Agent -> GoalProgress -> Bool
isGoalSatisfied agent progress =
  progressMetric progress >= 0.9   -- 90% completion threshold
  && progressObservations progress > 5

isGoalFailing :: Agent -> GoalProgress -> Bool
isGoalFailing agent progress =
  progressObservations progress > 30  -- Many observations
  && progressMetric progress < 0.3    -- But little progress

-- ── Goal diversity (swarm should have varied goals) ──────────────────────────────

goalDiversity :: [Agent] -> Double
goalDiversity agents =
  if null agents
  then 0.0
  else
    let goals = map (agentGoal . decision) agents
        uniqueGoals = length $ filter (\g -> length (filter (== g) goals) == 1) goals
    in fromIntegral uniqueGoals / fromIntegral (length agents)

-- Export: goals summary
goalsReport :: [Agent] -> String
goalsReport agents =
  let header = "═══ Swarm Goal Report ═══\n"
      byGoal = countGoalsByType agents
      diversity = goalDiversity agents
      stats = "Total Agents: " ++ show (length agents)
           ++ " | Goal Diversity: " ++ show (roundTo 2 diversity) ++ "\n"
      breakdown = intercalate "\n"
        [ "  " ++ show gt ++ ": " ++ show count
        | (gt, count) <- byGoal
        ]
  in header ++ stats ++ "\nBreakdown:\n" ++ breakdown

countGoalsByType :: [Agent] -> [(GoalType, Int)]
countGoalsByType agents =
  let goals = map (agentGoal . decision) agents
      explore = length $ filter isExploreGoal goals
      mapGoal = length $ filter isMapGoal goals
      detect = length $ filter isDetectGoal goals
      collab = length $ filter isCollabGoal goals
  in [ (GoalExplore, explore)
     , (GoalMap, mapGoal)
     , (GoalDetect, detect)
     , (GoalCollaborate, collab)
     ]

isExploreGoal :: Goal -> Bool
isExploreGoal (Explore _) = True
isExploreGoal _ = False

isMapGoal :: Goal -> Bool
isMapGoal (Map _) = True
isMapGoal _ = False

isDetectGoal :: Goal -> Bool
isDetectGoal (Detect _) = True
isDetectGoal _ = False

isCollabGoal :: Goal -> Bool
isCollabGoal (Collaborate _) = True
isCollabGoal _ = False

-- Rounding helper
roundTo :: Int -> Double -> Double
roundTo n x = fromIntegral (round (x * 10^n) :: Integer) / 10^n
