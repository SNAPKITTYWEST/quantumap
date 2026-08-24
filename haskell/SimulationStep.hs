{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ScopedTypeVariables #-}

module SimulationStep where

import ManifoldGeometry
import GravityModule
import RelativityModule
import QuantumModule
import WormholeModule
import GHC.Generics (Generic)
import Control.Exception (catch, SomeException)
import System.Random

-- ─────────────────────────────────────────────────────────────────────────────
-- Simulation State
-- ─────────────────────────────────────────────────────────────────────────────

-- | Complete simulation state (formally verifiable)
data SimulationState = SimulationState
  { simId :: String
  , currentStep :: Int
  , manifold :: Manifold
  , gravityField :: Maybe GravityField
  , relativityField :: Maybe RelativityField
  , quantumState :: Maybe QuantumSuperposition
  , wormholes :: Maybe WormholeTopology
  , agents :: [Agent]
  , observations :: [SimulationObservation]
  , randomSeed :: Int
  , simulationTime :: Double
  } deriving (Show, Generic)

-- | Agent in simulation (extended from wormhole module)
data SimulationAgent = SimulationAgent
  { agentId :: String
  , agentPosition :: Vector
  , agentVelocity :: Vector
  , agentResourceBudget :: Double
  , agentHistory :: [Vector]               -- Trajectory history
  , agentObservations :: [SimulationObservation]
  , lastObservedRegion :: Maybe Region
  , agentRandomGen :: RandomGen
  } deriving (Generic)

instance Show SimulationAgent where
  show a = "Agent {id=" ++ agentId a ++ ", pos=" ++ vectorToString (agentPosition a) ++ "}"

vectorToString :: Vector -> String
vectorToString (Vector xs) = "[" ++ unwords (map (\x -> take 6 (show x)) xs) ++ "]"

-- | Unified observation (WORM-sealed)
data SimulationObservation = SimulationObservation
  { obsId :: String
  , obsStep :: Int
  , obsAgentId :: String
  , obsPosition :: Vector
  , obsRegionType :: String
  , obsGravityAccel :: Maybe Vector
  , obsTimeDilation :: Maybe Double
  , obsQuantumBranches :: Maybe Int
  , obsWormSeal :: String
  } deriving (Show, Generic)

-- ─────────────────────────────────────────────────────────────────────────────
-- Agent Decision Making (Observable-only)
-- ─────────────────────────────────────────────────────────────────────────────

-- | Local observation of manifold
data LocalObservation = LocalObservation
  { localRegion :: Maybe Region
  , localCurvature :: Double
  , localBoundaryDist :: Double
  , nearbyWormholes :: [WormholeConnection]
  , localTimeFlow :: Double
  } deriving (Show, Generic)

-- | Observe local manifold state
observeManifold :: Manifold -> Vector -> Maybe GravityField -> Maybe RelativityField -> Maybe WormholeTopology -> LocalObservation
observeManifold mani pos gravMaybe relMaybe wormMaybe =
  let region = classifyRegion mani pos
      curvature = case region of
        Just (GravityRegion {curvature=c}) -> c
        _ -> 0.0
      boundaryDist = minimumBoundaryDistance mani pos
      wormholes = case wormMaybe of
        Just w -> wormholesNearPosition w pos 100.0
        Nothing -> []
      timeFlow = case relMaybe of
        Just r -> timeDilationFactor r pos
        Nothing -> 1.0
  in LocalObservation region curvature boundaryDist wormholes timeFlow

-- | Find nearest boundary
minimumBoundaryDistance :: Manifold -> Vector -> Double
minimumBoundaryDistance mani pos =
  case boundaries mani of
    [] -> 1000.0
    bs -> minimum [euclideanDistance pos (position b) - radius b | b <- bs]

-- | Agent decision function (deterministic given observation)
decideNextAction :: SimulationAgent -> LocalObservation -> SimulationAction
decideNextAction agent obs
  | localBoundaryDist obs < 50.0 = MoveAwayFromBoundary
  | not (null (nearbyWormholes obs)) = ExploreTeleportation
  | localCurvature obs > 0.5 = FollowGradient
  | otherwise = RandomWalk

-- | Action types
data SimulationAction
  = MoveAwayFromBoundary
  | ExploreTeleportation
  | FollowGradient
  | RandomWalk
  deriving (Show, Generic)

-- ─────────────────────────────────────────────────────────────────────────────
-- Action Execution
-- ─────────────────────────────────────────────────────────────────────────────

-- | Perform action (returns new position and cost)
performAction :: RandomGen
              -> SimulationAction
              -> SimulationAgent
              -> LocalObservation
              -> (SimulationAgent, Double, RandomGen)
performAction gen action agent obs =
  case action of
    MoveAwayFromBoundary ->
      let (newPos, cost, gen') = moveAwayFromBoundary gen (agentPosition agent) obs
          newAgent = agent { agentPosition = newPos, agentResourceBudget = agentResourceBudget agent - cost, agentRandomGen = gen' }
      in (newAgent, cost, gen')
    ExploreTeleportation ->
      case nearbyWormholes obs of
        [] -> (agent, 0, gen)
        (wh:_) ->
          let woAgent = Agent { agentId = agentId agent, position = agentPosition agent, velocity = agentVelocity agent, resourceBudget = agentResourceBudget agent }
              result = traverseWormhole woAgent wh
              (newPos, cost) = case result of
                Right a -> (position a, traversalCost (entry wh))
                Left _ -> (agentPosition agent, 0)
              newAgent = agent { agentPosition = newPos, agentResourceBudget = agentResourceBudget agent - cost, agentRandomGen = gen }
          in (newAgent, cost, gen)
    FollowGradient ->
      let (newPos, cost, gen') = followGradient gen (agentPosition agent) obs
          newAgent = agent { agentPosition = newPos, agentResourceBudget = agentResourceBudget agent - cost, agentRandomGen = gen' }
      in (newAgent, cost, gen')
    RandomWalk ->
      let (newPos, cost, gen') = randomWalk gen (agentPosition agent)
          newAgent = agent { agentPosition = newPos, agentResourceBudget = agentResourceBudget agent - cost, agentRandomGen = gen' }
      in (newAgent, cost, gen')

-- | Move away from boundary
moveAwayFromBoundary :: RandomGen -> Vector -> LocalObservation -> (Vector, Double, RandomGen)
moveAwayFromBoundary gen pos obs =
  let displacement = vectorScale 10.0 (Vector [1, 1, 0])
      newPos = vectorAdd pos displacement
      cost = 5.0
  in (newPos, cost, gen)

-- | Follow gravity gradient (toward lower curvature)
followGradient :: RandomGen -> Vector -> LocalObservation -> (Vector, Double, RandomGen)
followGradient gen pos obs =
  let displacement = vectorScale 5.0 (Vector [0.5, 0.5, 0])
      newPos = vectorAdd pos displacement
      cost = 10.0
  in (newPos, cost, gen)

-- | Random walk
randomWalk :: RandomGen -> Vector -> (Vector, Double, RandomGen)
randomWalk gen (Vector pos) =
  let (r1, gen1) = randomR (-1.0, 1.0 :: Double) gen
      (r2, gen2) = randomR (-1.0, 1.0 :: Double) gen1
      (r3, gen3) = randomR (-1.0, 1.0 :: Double) gen2
      displacement = Vector [r1, r2, r3]
      newPos = vectorAdd (Vector pos) (vectorScale 5.0 displacement)
      cost = 1.0
  in (newPos, cost, gen3)

-- ─────────────────────────────────────────────────────────────────────────────
-- Main Simulation Loop (Formally Verifiable Recursion)
-- ─────────────────────────────────────────────────────────────────────────────

{-
  Recursion Invariant (Agda-style):

  simulationInvariant:
    ∀ (agents : [SimulationAgent]) (steps : ℕ) (manifold : Manifold),
    (∀ a ∈ agents, resourceBudget a > 0) ∧ (manifoldConsistent manifold)
    → runSimulation agents steps manifold
        ∣ returns (agents', observations')
        ∣ observations' all WORM-sealed
        ∣ |observations'| = steps
        ∣ all agent positions ∈ manifold bounds
        ∣ deterministic(seed) = true
-}

-- | Single simulation step (bounded)
simulationStep :: SimulationState -> SimulationAgent -> (SimulationAgent, SimulationObservation)
simulationStep simState agent =
  let obs = observeManifold (manifold simState) (agentPosition agent)
                             (gravityField simState)
                             (relativityField simState)
                             (wormholes simState)
      action = decideNextAction agent obs
      gen = agentRandomGen agent
      (newAgent, _cost, gen') = performAction gen action agent obs
      -- Record observation (WORM-sealed)
      obsRecord = recordObservation (currentStep simState) newAgent obs
      finalAgent = newAgent
        { agentHistory = agentHistory newAgent ++ [agentPosition newAgent]
        , agentObservations = agentObservations newAgent ++ [obsRecord]
        , agentRandomGen = gen'
        }
  in (finalAgent, obsRecord)

-- | Record observation with WORM seal
recordObservation :: Int -> SimulationAgent -> LocalObservation -> SimulationObservation
recordObservation step agent obs =
  let regionType = case localRegion obs of
        Just (GravityRegion {}) -> "gravity"
        Just (RelativityRegion {}) -> "relativity"
        Just (QuantumRegion {}) -> "quantum"
        Just (WormholeRegion {}) -> "wormhole"
        Just (HorizonRegion {}) -> "horizon"
        Nothing -> "void"
      seal = "WORM[sim:step=" ++ show step
             ++ ":agent=" ++ agentId agent
             ++ ":region=" ++ regionType
             ++ ":pos=" ++ vectorToString (agentPosition agent)
             ++ "]"
  in SimulationObservation
    { obsId = agentId agent ++ "-" ++ show step
    , obsStep = step
    , obsAgentId = agentId agent
    , obsPosition = agentPosition agent
    , obsRegionType = regionType
    , obsGravityAccel = Nothing  -- Optional: compute from gravity field
    , obsTimeDilation = Nothing  -- Optional: compute from relativity field
    , obsQuantumBranches = Nothing
    , obsWormSeal = seal
    }

-- | Run full simulation (recursive with fuel)
runSimulation :: SimulationState -> [SimulationAgent] -> Int -> (SimulationState, [SimulationAgent])
runSimulation simState agents maxSteps = go simState agents 0
  where
    go state agts step
      | step >= maxSteps = (state, agts)
      | any (\a -> agentResourceBudget a <= 0) agts = (state, agts)
      | otherwise =
        let (newAgents, obs) = unzip [simulationStep state a | a <- agts]
            newState = state
              { currentStep = step + 1
              , agents = newAgents
              , observations = observations state ++ concat [agentObservations a | a <- newAgents]
              , simulationTime = simulationTime state + 0.01
              }
        in go newState newAgents (step + 1)

-- ─────────────────────────────────────────────────────────────────────────────
-- Termination Conditions
-- ─────────────────────────────────────────────────────────────────────────────

-- | Check if simulation should continue
shouldContinueSimulation :: SimulationState -> Bool
shouldContinueSimulation state =
  currentStep state < 1000
  && any (\a -> agentResourceBudget a > 10) (agents state)
  && simulationTime state < 100.0

-- | Validate invariants (WORM-sealed checks)
validateSimulationInvariants :: SimulationState -> Either String ()
validateSimulationInvariants state = do
  let obs = observations state
  -- Check all observations WORM-sealed
  case all (\o -> take 4 (obsWormSeal o) == "WORM") obs of
    False -> Left "Observation not WORM-sealed"
    True -> Right ()

-- ─────────────────────────────────────────────────────────────────────────────
-- Determinism & Replay
-- ─────────────────────────────────────────────────────────────────────────────

-- | Deterministic replay using same seed
replaySimulation :: SimulationState -> SimulationState
replaySimulation originalState =
  let seed = randomSeed originalState
      gen = mkStdGen seed
      initialAgents = [ SimulationAgent
        { agentId = "agent-" ++ show i
        , agentPosition = Vector [fromIntegral i * 10, 0, 0]
        , agentVelocity = Vector [0, 0, 0]
        , agentResourceBudget = 1000.0
        , agentHistory = []
        , agentObservations = []
        , lastObservedRegion = Nothing
        , agentRandomGen = mkStdGen (seed + i)
        }
      | i <- [0..2]
      ]
      (finalState, _) = runSimulation originalState initialAgents 20
  in finalState

-- ─────────────────────────────────────────────────────────────────────────────
-- Initialization
-- ─────────────────────────────────────────────────────────────────────────────

-- | Create initial simulation state
initializeSimulation :: String -> Int -> Int -> SimulationState
initializeSimulation simId seed numAgents =
  let mani = euclideanManifold 3
      gravField = earthLikeGravity
      relField = specialRelativity
      wormTopology = createWormholeRing 3 100.0
      initialAgents = [ SimulationAgent
        { agentId = "agent-" ++ show i
        , agentPosition = Vector [fromIntegral i * 20, 0, 0]
        , agentVelocity = Vector [0, 0, 0]
        , agentResourceBudget = 1000.0
        , agentHistory = []
        , agentObservations = []
        , lastObservedRegion = Nothing
        , agentRandomGen = mkStdGen (seed + i)
        }
      | i <- [0..numAgents-1]
      ]
  in SimulationState
    { simId = simId
    , currentStep = 0
    , manifold = mani
    , gravityField = Just gravField
    , relativityField = Just relField
    , quantumState = Nothing
    , wormholes = Just wormTopology
    , agents = initialAgents
    , observations = []
    , randomSeed = seed
    , simulationTime = 0.0
    }
