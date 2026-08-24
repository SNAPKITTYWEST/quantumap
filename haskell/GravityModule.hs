{-# LANGUAGE DeriveGeneric #-}

module GravityModule where

import ManifoldGeometry
import GHC.Generics (Generic)

-- ─────────────────────────────────────────────────────────────────────────────
-- Gravity Simulation
-- ─────────────────────────────────────────────────────────────────────────────

-- | Point mass source
data PointMass = PointMass
  { massMagnitude :: Double
  , massPosition :: Vector
  } deriving (Show, Generic)

-- | Gravity field (collection of masses + derived fields)
data GravityField = GravityField
  { gravityFieldId :: String
  , masses :: [PointMass]
  , g :: Double                       -- Gravitational constant
  , softening :: Double               -- Softening length (avoid singularities)
  } deriving (Show, Generic)

-- ─────────────────────────────────────────────────────────────────────────────
-- Gravitational Acceleration
-- ─────────────────────────────────────────────────────────────────────────────

-- | Gravitational acceleration at a point (simplified Newtonian)
-- a_i = -G * Σ(M_j * (r_i - r_j) / |r_i - r_j|^3)
accelerationAtPoint :: GravityField -> Vector -> Vector
accelerationAtPoint field pos =
  let accelVectors = map (accelerationFromMass field pos) (masses field)
  in foldl1 vectorAdd accelVectors

-- | Acceleration from single point mass
accelerationFromMass :: GravityField -> Vector -> PointMass -> Vector
accelerationFromMass field pos mass =
  let r = vectorSub (massPosition mass) pos              -- vector to mass
      r_mag = vectorNorm r
      r_mag_soft = sqrt (r_mag * r_mag + softening field * softening field)
      -- Avoid division by zero
      a_mag = if r_mag_soft > 0
              then -(g field * massMagnitude mass) / (r_mag_soft * r_mag_soft * r_mag_soft)
              else 0
  in vectorScale a_mag r

-- ─────────────────────────────────────────────────────────────────────────────
-- Curvature Tensor (Simplified Riemann Scalar)
-- ─────────────────────────────────────────────────────────────────────────────

-- | Scalar curvature at point (R = Σ 8πG ρ where ρ is mass density)
-- Simplified: use inverse-square law scaling
scalarCurvatureAtPoint :: GravityField -> Vector -> Double
scalarCurvatureAtPoint field pos =
  let contributions = map (curvatureFromMass field pos) (masses field)
  in sum contributions

-- | Curvature contribution from single mass
curvatureFromMass :: GravityField -> Vector -> PointMass -> Double
curvatureFromMass field pos mass =
  let distance = euclideanDistance pos (massPosition mass)
      distance_soft = sqrt (distance * distance + softening field * softening field)
  in if distance_soft > 0
     then (g field * massMagnitude mass) / (distance_soft * distance_soft)
     else 0

-- ─────────────────────────────────────────────────────────────────────────────
-- Trajectory Prediction (Geodesic Integration)
-- ─────────────────────────────────────────────────────────────────────────────

-- | Velocity vector
newtype Velocity = Velocity Vector
  deriving (Show)

-- | Geodesic step using Verlet integration
-- x(t+dt) = x(t) + v(t)*dt + 0.5*a(t)*dt^2
geodesicStep :: GravityField -> Vector -> Velocity -> Double -> (Vector, Velocity)
geodesicStep field pos (Velocity vel) dt =
  let accel = accelerationAtPoint field pos
      newPos = pos `vectorAdd` vectorScale dt vel `vectorAdd` vectorScale (0.5 * dt * dt) accel
      -- v(t+dt) = v(t) + a(t)*dt
      newAccel = accelerationAtPoint field newPos
      avgAccel = vectorScale 0.5 (accel `vectorAdd` newAccel)
      newVel = vel `vectorAdd` vectorScale dt avgAccel
  in (newPos, Velocity newVel)

-- | Predict trajectory over N steps
predictTrajectory :: GravityField -> Vector -> Velocity -> Double -> Int -> [Vector]
predictTrajectory field pos vel dt steps =
  let go _ [] = []
      go (p, v) (i:rest) =
        let (newP, newV) = geodesicStep field p v dt
        in newP : go (newP, newV) rest
  in pos : go (pos, vel) [1..steps-1]

-- | Trace trajectory until boundary or max steps
traceTrajectoryUntilBoundary :: GravityField -> Manifold -> Vector -> Velocity -> Double -> Int -> [Vector]
traceTrajectoryUntilBoundary field manifold pos vel dt maxSteps =
  go pos vel 0 []
  where
    go p v step acc
      | step >= maxSteps = reverse acc
      | not (pointInBounds manifold p) = reverse acc
      | otherwise =
        let (newP, newV) = geodesicStep field p v dt
        in go newP newV (step + 1) (newP : acc)

-- ─────────────────────────────────────────────────────────────────────────────
-- Gravitational Lensing (Light deflection)
-- ─────────────────────────────────────────────────────────────────────────────

-- | Deflection angle for light ray passing near mass
-- θ ≈ 4GM/(c^2 b) where b is impact parameter
lightDeflectionAngle :: GravityField -> Vector -> Vector -> Double
lightDeflectionAngle field lightPos impactVec =
  let bImpactParam = minimum [euclideanDistance lightPos (massPosition m) | m <- masses field]
      c = 299792458.0  -- speed of light (m/s)
      totalMass = sum [massMagnitude m | m <- masses field]
      theta = if bImpactParam > 0
              then (4.0 * g field * totalMass) / (c * c * bImpactParam)
              else 0
  in theta

-- ─────────────────────────────────────────────────────────────────────────────
-- WORM-sealed gravity observations
-- ─────────────────────────────────────────────────────────────────────────────

data GravityObservation = GravityObservation
  { obsStep :: Int
  , obsPosition :: Vector
  , obsAcceleration :: Vector
  , obsCurvature :: Double
  , obsWormSeal :: String
  } deriving (Show, Generic)

-- | WORM seal observation
sealGravityObservation :: Int -> Vector -> GravityField -> GravityObservation
sealGravityObservation step pos field =
  let accel = accelerationAtPoint field pos
      curv = scalarCurvatureAtPoint field pos
      seal = "WORM[gravity:step=" ++ show step
             ++ ":pos=" ++ vectorToString pos
             ++ ":accel=" ++ vectorToString accel
             ++ ":R=" ++ show (round (curv * 1000) :: Integer) ++ "]"
  in GravityObservation step pos accel curv seal

-- | Vector to string for sealing
vectorToString :: Vector -> String
vectorToString (Vector xs) = "[" ++ unwords (map (\x -> take 6 (show x)) xs) ++ "]"

-- ─────────────────────────────────────────────────────────────────────────────
-- Gravity Field Configuration
-- ─────────────────────────────────────────────────────────────────────────────

-- | Create earth-like gravity field
earthLikeGravity :: GravityField
earthLikeGravity = GravityField
  { gravityFieldId = "earth"
  , masses = [PointMass 5.972e24 (Vector [0, 0, 0])]
  , g = 6.674e-11
  , softening = 1.0
  }

-- | Create binary star system
binaryStarSystem :: GravityField
binaryStarSystem = GravityField
  { gravityFieldId = "binary-star"
  , masses =
    [ PointMass 1.989e30 (Vector [-1.5e11, 0, 0])
    , PointMass 1.989e30 (Vector [1.5e11, 0, 0])
    ]
  , g = 6.674e-11
  , softening = 1e9
  }

-- | Create black hole
blackHoleSystem :: Double -> GravityField
blackHoleSystem bh_mass = GravityField
  { gravityFieldId = "black-hole"
  , masses = [PointMass bh_mass (Vector [0, 0, 0])]
  , g = 6.674e-11
  , softening = 0.1  -- Schwarzschild radius ∝ M
  }
