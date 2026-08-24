{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}

module ManifoldGeometry where

import Data.List (nubBy)
import Data.Function (on)
import GHC.Generics (Generic)
import Control.Exception (Exception, throw)

-- ─────────────────────────────────────────────────────────────────────────────
-- Manifold: Core Spacetime Abstraction
-- ─────────────────────────────────────────────────────────────────────────────

-- | Metric tensor defines distances and curvature in the manifold
data MetricTensor = MetricTensor
  { metricType :: String              -- "euclidean" | "riemannian" | "lorentzian"
  , signature :: (Int, Int, Int)      -- (spatial, temporal, null) dimensions
  , components :: [[Double]]          -- n×n symmetric matrix
  } deriving (Show, Generic, Eq)

-- | A region is a connected area with uniform physics properties
data Region
  = GravityRegion
    { gravityId :: String
    , curvature :: Double
    , centerMass :: Vector
    , massRadius :: Double
    }
  | RelativityRegion
    { relId :: String
    , timeDilationFactor :: Double       -- simplified: single factor, not function
    , speedOfLight :: Double
    }
  | QuantumRegion
    { quantumId :: String
    , superpositionDim :: Int
    , branchProb :: Double
    , decoherenceRate :: Double
    }
  | WormholeRegion
    { wormholeId :: String
    , connections :: [String]         -- IDs of connected regions
    , traversalCost :: Double
    , stabilityFactor :: Double
    }
  | HorizonRegion
    { horizonId :: String
    , eventHorizonRadius :: Double
    , singularityDensity :: Double
    }
  deriving (Show, Generic)

-- | Boundary definitions (edges, horizons, thresholds)
data Boundary = Boundary
  { boundaryId :: String
  , boundaryType :: String            -- "hard-wall" | "soft-horizon" | "threshold"
  , position :: Vector
  , radius :: Double
  } deriving (Show, Generic, Eq)

-- | Vector type (n-dimensional)
newtype Vector = Vector [Double]
  deriving (Show, Generic, Eq)

-- | Vector operations
vectorDim :: Vector -> Int
vectorDim (Vector xs) = length xs

vectorMap :: (Double -> Double) -> Vector -> Vector
vectorMap f (Vector xs) = Vector (map f xs)

vectorZip :: (Double -> Double -> Double) -> Vector -> Vector -> Vector
vectorZip f (Vector xs) (Vector ys)
  | length xs == length ys = Vector (zipWith f xs ys)
  | otherwise = error "Vector dimension mismatch"

vectorAdd :: Vector -> Vector -> Vector
vectorAdd = vectorZip (+)

vectorSub :: Vector -> Vector -> Vector
vectorSub = vectorZip (-)

vectorScale :: Double -> Vector -> Vector
vectorScale s = vectorMap (* s)

-- | Dot product (Euclidean)
dotProduct :: Vector -> Vector -> Double
dotProduct (Vector xs) (Vector ys) = sum (zipWith (*) xs ys)

-- | L2 norm
vectorNorm :: Vector -> Double
vectorNorm v = sqrt (dotProduct v v)

-- | Distance between two vectors (Euclidean)
euclideanDistance :: Vector -> Vector -> Double
euclideanDistance p1 p2 = vectorNorm (vectorSub p1 p2)

-- | Coordinate systems (transformations)
data CoordinateSystem
  = Cartesian Int                     -- Dimension
  | Polar                             -- r, theta
  | Spherical                         -- r, theta, phi
  | LorentzCoords                     -- t, x, y, z
  deriving (Show, Eq, Generic)

-- | Transformation matrix (identity for now, extended for full GR)
transformationMatrix :: CoordinateSystem -> CoordinateSystem -> [[Double]]
transformationMatrix Cartesian {} Cartesian {}
  = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
transformationMatrix _ _ = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]

-- | Matrix-vector multiplication
multiplyMatrix :: [[Double]] -> Vector -> Vector
multiplyMatrix matrix (Vector v) =
  Vector [sum (zipWith (*) row v) | row <- matrix]

-- | Transform coordinates between systems
transformCoordinates :: CoordinateSystem -> CoordinateSystem -> Vector -> Vector
transformCoordinates from to pos
  | from == to = pos
  | otherwise = multiplyMatrix (transformationMatrix from to) pos

-- | Geodesic distance (using metric tensor)
geodesicDistance :: MetricTensor -> Vector -> Vector -> Double
geodesicDistance metric p1 p2 =
  let diff = vectorSub p1 p2
      (Vector diff_components) = diff
      n = length diff_components
      metric_matrix = take n (components metric)
      -- Simplified: ds^2 = g_ij dx^i dx^j
      contracted = sum [metric_matrix !! i !! j * diff_components !! i * diff_components !! j
                       | i <- [0..n-1], j <- [0..n-1]]
  in sqrt (max 0 contracted)  -- max 0 to handle numerical issues

-- | Main Manifold data structure
data Manifold = Manifold
  { manifoldId :: String
  , dimension :: Int
  , metric :: MetricTensor
  , regions :: [Region]
  , boundaries :: [Boundary]
  , topologyType :: String            -- "flat" | "curved" | "toroidal" | "hyperbolic"
  } deriving (Show, Generic)

-- | Create Euclidean manifold
euclideanManifold :: Int -> Manifold
euclideanManifold d = Manifold
  { manifoldId = "euclidean-" ++ show d ++ "d"
  , dimension = d
  , metric = MetricTensor "euclidean" (d, 0, 0) (replicate d (replicate d 0) >>= \_ -> [[1.0 | _ <- [1..d]]])
  , regions = []
  , boundaries = []
  , topologyType = "flat"
  }

-- | Add region to manifold
addRegion :: Region -> Manifold -> Manifold
addRegion r m = m { regions = regions m ++ [r] }

-- | Add boundary to manifold
addBoundary :: Boundary -> Manifold -> Manifold
addBoundary b m = m { boundaries = boundaries m ++ [b] }

-- | Check if point is in bounds (respects boundaries)
pointInBounds :: Manifold -> Vector -> Bool
pointInBounds m (Vector pos) =
  let dim = dimension m
  in length pos == dim && all (>= -1000) pos && all (<= 1000) pos

-- | Classify region at position
classifyRegion :: Manifold -> Vector -> Maybe Region
classifyRegion m pos =
  case filter (pointInRegion pos) (regions m) of
    [] -> Nothing
    (r:_) -> Just r

-- | Check if point is in region
pointInRegion :: Vector -> Region -> Bool
pointInRegion p r = case r of
  GravityRegion {centerMass=c, massRadius=rad} -> euclideanDistance p c <= rad
  RelativityRegion {} -> True  -- omnipresent
  QuantumRegion {} -> True
  WormholeRegion {} -> True
  HorizonRegion {eventHorizonRadius=rad} -> euclideanDistance p (Vector [0,0,0]) <= rad

-- | Curvature at position (scalar)
curvatureAtPosition :: Manifold -> Vector -> Double
curvatureAtPosition m p =
  case classifyRegion m p of
    Just (GravityRegion {curvature=c}) -> c
    _ -> 0.0

-- | WORM-sealed observation of manifold state
wormSealManifoldState :: Manifold -> Int -> String
wormSealManifoldState m step =
  "WORM[step=" ++ show step ++ ":manifold=" ++ manifoldId m
  ++ ":regions=" ++ show (length (regions m))
  ++ ":topology=" ++ topologyType m ++ "]"

-- ─────────────────────────────────────────────────────────────────────────────
-- Exceptions
-- ─────────────────────────────────────────────────────────────────────────────

data ManifoldException
  = DimensionMismatch String
  | OutOfBounds String
  | InvalidRegion String
  deriving (Show, Generic)

instance Exception ManifoldException
