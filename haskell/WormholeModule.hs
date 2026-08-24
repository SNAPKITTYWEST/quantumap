{-# LANGUAGE DeriveGeneric #-}

module WormholeModule where

import ManifoldGeometry hiding (traversalCost, position, connections, stabilityFactor)
import GHC.Generics (Generic)
import Data.List (find)

-- ─────────────────────────────────────────────────────────────────────────────
-- Wormhole Topology: Non-Euclidean Shortcuts
-- ─────────────────────────────────────────────────────────────────────────────

-- | Wormhole entry point
data WormholeEntry = WormholeEntry
  { entryId :: String
  , entryPosition :: Vector
  , targetExitId :: String              -- Reference to exit
  , stabilityFactor :: Double           -- 0-1: how stable is this wormhole?
  , traversalCost :: Double             -- Energy/resource cost
  , jitterRadius :: Double              -- Random scatter on exit
  } deriving (Show, Generic, Eq)

-- | Wormhole exit point
data WormholeExit = WormholeExit
  { exitId :: String
  , exitPosition :: Vector
  , sourceEntryId :: String             -- Backreference to entry
  , exitStability :: Double
  } deriving (Show, Generic, Eq)

-- | Complete wormhole connection
data WormholeConnection = WormholeConnection
  { connectionId :: String
  , entry :: WormholeEntry
  , exit :: WormholeExit
  , metricDistance :: Double            -- Euclidean distance
  , topologicalDistance :: Double       -- Through wormhole (always < metricDistance)
  , traversabilityScore :: Double       -- Can we go through? (0-1)
  } deriving (Show, Generic, Eq)

-- ─────────────────────────────────────────────────────────────────────────────
-- Wormhole Topology (Collection of wormholes in a region)
-- ─────────────────────────────────────────────────────────────────────────────

data WormholeTopology = WormholeTopology
  { topologyId :: String
  , connections :: [WormholeConnection]
  , manifoldReference :: Maybe Manifold
  } deriving (Show, Generic)

-- ─────────────────────────────────────────────────────────────────────────────
-- Wormhole Physics
-- ─────────────────────────────────────────────────────────────────────────────

-- | Morris-Thorne wormhole metric (simplified)
-- Throat radius: a
-- Redshift function: Φ(r)
-- Spatial part: dl² = (dr² + (r² + a²)(dθ² + sin²θ dφ²)) / (1 + a²/r²)
data MorrisThorneMeter = MorrisThorneMeter
  { throatRadius :: Double
  , redshiftFunction :: Double -> Double   -- Φ(r)
  , shape :: Double -> Double               -- b(r) - shape function
  } deriving (Generic)

instance Show MorrisThorneMeter where
  show m = "MorrisThorneMeter {throat=" ++ show (throatRadius m) ++ "}"

-- | Exotic matter (negative energy) requirement
exoticMatterDensity :: Double -> Double -> Double
exoticMatterDensity radius throatRadius =
  let rho_planck = 1.0 / (1.616e-35 ^ 3)  -- Planck density (rough)
      rho_exoticRequired = -rho_planck / (radius * radius)
  in rho_exoticRequired

-- ─────────────────────────────────────────────────────────────────────────────
-- Wormhole Traversal
-- ─────────────────────────────────────────────────────────────────────────────

-- | Agent position after traversal
data Agent = Agent
  { agentId :: String
  , position :: Vector
  , velocity :: Vector
  , resourceBudget :: Double            -- Energy for traversal
  } deriving (Show, Generic)

-- | Traverse wormhole (if stable and affordable)
traverseWormhole :: Agent -> WormholeConnection -> Either String Agent
traverseWormhole agent conn =
  let requiredCost = traversalCost (entry conn)
      requiredStability = traversabilityScore conn
      hasResources = resourceBudget agent >= requiredCost
      isStable = requiredStability > 0.5
  in case (hasResources, isStable) of
    (True, True) ->
      let newPos = exitPosition (exit conn)
          newAgent = agent
            { position = newPos
            , resourceBudget = resourceBudget agent - requiredCost
            }
      in Right newAgent
    (False, _) -> Left "Insufficient resources for wormhole traversal"
    (_, False) -> Left "Wormhole too unstable for safe traversal"

-- | Stochastic wormhole fluctuation (can trap agent)
wormholeFluctuation :: Double -> Double -> Double
wormholeFluctuation stability randomFactor =
  let fluxStrength = (1.0 - stability) * randomFactor
  in fluxStrength

-- | Probability of getting trapped in wormhole
trapProbability :: Double -> Double
trapProbability stability =
  (1.0 - stability) * (1.0 - stability)

-- ─────────────────────────────────────────────────────────────────────────────
-- Wormhole Stability (Time-dependent)
-- ─────────────────────────────────────────────────────────────────────────────

-- | Stability evolves with time (wormholes decay)
-- S(t) = S₀ * exp(-t/τ) where τ is lifetime
stabilityAtTime :: Double -> Double -> Double -> Double
stabilityAtTime s0 lifetime time =
  let decayFactor = exp (-time / max 0.001 lifetime)
  in s0 * decayFactor

-- | Remnant wormhole (completely decayed)
isWormholeRemnant :: WormholeConnection -> Double -> Bool
isWormholeRemnant conn time =
  stabilityAtTime (traversabilityScore conn) 10.0 time < 0.01

-- ─────────────────────────────────────────────────────────────────────────────
-- Geodesic Shortcuts
-- ─────────────────────────────────────────────────────────────────────────────

-- | Proper distance (metric) vs topological distance
properDistance :: WormholeConnection -> Double
properDistance conn = metricDistance conn

-- | Time savings from using wormhole
timeSavings :: WormholeConnection -> Double -> Double
timeSavings conn speedOfLight =
  let proper_time = properDistance conn / speedOfLight
      topo_time = topologicalDistance conn / speedOfLight
  in proper_time - topo_time

-- ─────────────────────────────────────────────────────────────────────────────
-- Kaluza-Klein Wormholes (Higher dimensions)
-- ─────────────────────────────────────────────────────────────────────────────

-- | Extra dimension compactification radius
data KaluzaKleinWormhole = KaluzaKleinWormhole
  { kk_entry :: WormholeEntry
  , kk_exit :: WormholeExit
  , compactificationRadius :: Double   -- Size of extra dimension
  , excitationLevel :: Int              -- Kaluza-Klein mode (0, 1, 2, ...)
  } deriving (Show, Generic, Eq)

-- | Mass of Kaluza-Klein modes
kaluzaKleinMass :: Double -> Int -> Double
kaluzaKleinMass compRadius level =
  let m_pl = 2.176e-8  -- Planck mass (kg)
      n = fromIntegral level :: Double
  in m_pl * sqrt (1.0 + (n / compRadius) ^ 2)

-- ─────────────────────────────────────────────────────────────────────────────
-- Wormhole Network
-- ─────────────────────────────────────────────────────────────────────────────

-- | Find all wormholes near a position
wormholesNearPosition :: WormholeTopology -> Vector -> Double -> [WormholeConnection]
wormholesNearPosition topology pos radius =
  filter (\c -> euclideanDistance pos (entryPosition (entry c)) < radius)
         (connections topology)

-- | Shortest path through wormhole network (greedy approximation)
shortestWormholePath :: WormholeTopology -> Vector -> Vector -> [WormholeConnection]
shortestWormholePath topology start goal =
  greedySearch start goal (connections topology) []
  where
    greedySearch pos _ [] path = reverse path
    greedySearch pos goal available path
      | euclideanDistance pos goal < 1.0 = reverse path
      | null available = reverse path
      | otherwise =
        let best = minimumBy (compareDistance goal) available
            newAvail = filter (/= best) available
            newPos = exitPosition (exit best)
        in greedySearch newPos goal newAvail (best : path)

    compareDistance goal c1 c2 =
      compare (euclideanDistance goal (exitPosition (exit c1)))
              (euclideanDistance goal (exitPosition (exit c2)))

-- | Greedy minimum selection
minimumBy :: (a -> a -> Ordering) -> [a] -> a
minimumBy _ [] = error "empty list"
minimumBy cmp (x:xs) = foldl selectMin x xs
  where selectMin a b = if cmp a b == LT then a else b

-- ─────────────────────────────────────────────────────────────────────────────
-- Wormhole Throat Metric
-- ─────────────────────────────────────────────────────────────────────────────

-- | Lapse function (time dilation in wormhole throat)
lapseFunction :: Double -> Double -> Double
lapseFunction r a = sqrt (1.0 + (a / r) ^ 2)

-- | Radial coordinate in wormhole (r < a is forbidden)
throatCoordinate :: Double -> Double -> Double
throatCoordinate r a =
  if r < a then a else r

-- ─────────────────────────────────────────────────────────────────────────────
-- WORM-sealed wormhole observations
-- ─────────────────────────────────────────────────────────────────────────────

data WormholeObservation = WormholeObservation
  { whStep :: Int
  , whPosition :: Vector
  , whNearbyWormholes :: Int
  , whStabilitySum :: Double
  , whWormSeal :: String
  } deriving (Show, Generic)

-- | WORM seal observation
sealWormholeObservation :: Int -> Vector -> WormholeTopology -> WormholeObservation
sealWormholeObservation step pos topology =
  let nearby = wormholesNearPosition topology pos 100.0
      numNearby = length nearby
      totalStability = sum [traversabilityScore c | c <- nearby]
      seal = "WORM[wormhole:step=" ++ show step
             ++ ":pos=" ++ vectorToString pos
             ++ ":nearby_wormholes=" ++ show numNearby
             ++ ":total_stability=" ++ show (round (totalStability * 100) :: Integer) ++ "]"
  in WormholeObservation step pos numNearby totalStability seal

-- | Vector to string for sealing
vectorToString :: Vector -> String
vectorToString (Vector xs) = "[" ++ unwords (map (\x -> take 6 (show x)) xs) ++ "]"

-- ─────────────────────────────────────────────────────────────────────────────
-- Predefined Wormhole Networks
-- ─────────────────────────────────────────────────────────────────────────────

-- | Create simple binary wormhole (entry-exit pair)
createBinaryWormhole :: String -> Vector -> Vector -> WormholeConnection
createBinaryWormhole id entryPos exitPos =
  let metric = euclideanDistance entryPos exitPos
      topo = metric * 0.3  -- Wormhole shortens distance to 30%
      entry = WormholeEntry
        { entryId = id ++ "-entry"
        , entryPosition = entryPos
        , targetExitId = id ++ "-exit"
        , stabilityFactor = 0.8
        , traversalCost = 100.0
        , jitterRadius = 10.0
        }
      exit = WormholeExit
        { exitId = id ++ "-exit"
        , exitPosition = exitPos
        , sourceEntryId = id ++ "-entry"
        , exitStability = 0.8
        }
  in WormholeConnection
    { connectionId = id
    , entry = entry
    , exit = exit
    , metricDistance = metric
    , topologicalDistance = topo
    , traversabilityScore = 0.8
    }

-- | Create wormhole ring (cyclic topology)
createWormholeRing :: Int -> Double -> WormholeTopology
createWormholeRing n radius =
  let positions = [ Vector [radius * cos (2*pi*fromIntegral i/fromIntegral n), radius * sin (2*pi*fromIntegral i/fromIntegral n), 0]
                  | i <- [0..n-1]
                  ]
      connections = [ createBinaryWormhole ("ring-" ++ show i)
                      (positions !! i)
                      (positions !! ((i+1) `mod` n))
                    | i <- [0..n-1]
                    ]
  in WormholeTopology
    { topologyId = "wormhole-ring-" ++ show n
    , connections = connections
    , manifoldReference = Nothing
    }
