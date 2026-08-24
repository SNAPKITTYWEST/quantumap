{-# LANGUAGE DeriveGeneric #-}

module RelativityModule where

import ManifoldGeometry
import GHC.Generics (Generic)

-- ─────────────────────────────────────────────────────────────────────────────
-- Relativity: Time Dilation & Coordinate Transforms
-- ─────────────────────────────────────────────────────────────────────────────

-- | Relativity field (observer-dependent time + light cones)
data RelativityField = RelativityField
  { relativityFieldId :: String
  , relativityTimeDilation :: Vector -> Double   -- Returns factor < 1 near gravity
  , localSpeedOfLight :: Double              -- Default 299792458 m/s
  , gravitationalTimeWarp :: Double -> Double  -- f(potential) -> time dilation
  , schwarzschildRadius :: Double            -- For event horizon
  } deriving (Generic)

instance Show RelativityField where
  show r = "RelativityField {id=" ++ relativityFieldId r ++ "}"

-- ─────────────────────────────────────────────────────────────────────────────
-- Time Dilation
-- ─────────────────────────────────────────────────────────────────────────────

-- | Local proper time: dτ = √(1 - v²/c²) √(1 - 2GM/rc²) dt
-- (Schwarzschild metric with velocity)
localProperTime :: RelativityField -> Vector -> Double -> Double -> Double
localProperTime field pos velocity globalTime =
  let c = localSpeedOfLight field
      -- Gravitational time dilation: √(1 - Rs/r)
      gravDilation = relativityTimeDilation field pos
      -- Kinetic time dilation: √(1 - v²/c²)
      beta = velocity / c
      beta_clamped = min 0.9999 (abs beta)  -- Clamp to avoid negative sqrt
      kineticDilation = sqrt (1.0 - beta_clamped * beta_clamped)
      -- Total: τ = dt * g_tt where g_tt combines both effects
  in globalTime * gravDilation * kineticDilation

-- | Gravitational potential time dilation
-- Near Schwarzschild: 1 - 2GM/(rc²) = 1 - Rs/r
schwarzschildTimeDilation :: Double -> Double -> Double -> Double
schwarzschildTimeDilation rs r c =
  sqrt (max 0.0001 (1.0 - rs / r))  -- Clamp to avoid negative sqrt

-- ─────────────────────────────────────────────────────────────────────────────
-- Coordinate Transformations (Special Relativity)
-- ─────────────────────────────────────────────────────────────────────────────

-- | Lorentz transformation (special relativity boost along x-axis)
-- x' = γ(x - βct)
-- t' = γ(t - βx/c)
-- where γ = 1/√(1 - β²), β = v/c
lorentzBoostX :: Double -> Vector -> Vector
lorentzBoostX velocity pos@(Vector coords) =
  let c = 299792458.0
      beta = velocity / c
      beta_clamped = min 0.9999 (abs beta)
      gamma = 1.0 / sqrt (1.0 - beta_clamped * beta_clamped)
      -- Assume coords = [ct, x, y, z]
      ct = if length coords > 0 then coords !! 0 else 0
      x = if length coords > 1 then coords !! 1 else 0
      y = if length coords > 2 then coords !! 2 else 0
      z = if length coords > 3 then coords !! 3 else 0
      ct' = gamma * (ct - beta_clamped * x)
      x' = gamma * (x - beta_clamped * ct)
      y' = y
      z' = z
  in Vector [ct', x', y', z']

-- | Inverse Lorentz boost
lorentzBoostXInverse :: Double -> Vector -> Vector
lorentzBoostXInverse velocity = lorentzBoostX (-velocity)

-- | General velocity boost (along arbitrary direction)
lorentzBoost :: Vector -> Vector -> Vector
lorentzBoost velocity pos =
  let c = 299792458.0
      v_mag = vectorNorm velocity
      beta = v_mag / c
      beta_clamped = min 0.9999 (abs beta)
  in if beta_clamped < 0.001
     then pos  -- Newtonian limit
     else lorentzBoostX v_mag pos

-- ─────────────────────────────────────────────────────────────────────────────
-- Spacetime Intervals
-- ─────────────────────────────────────────────────────────────────────────────

-- | Spacetime interval (invariant)
-- s² = -(cΔt)² + Δx² + Δy² + Δz²  (signature: -+++)
spacetimeInterval :: Vector -> Vector -> Double
spacetimeInterval (Vector p1) (Vector p2) =
  let dt = if length p1 > 0 && length p2 > 0 then p1 !! 0 - p2 !! 0 else 0
      dx = if length p1 > 1 && length p2 > 1 then p1 !! 1 - p2 !! 1 else 0
      dy = if length p1 > 2 && length p2 > 2 then p1 !! 2 - p2 !! 2 else 0
      dz = if length p1 > 3 && length p2 > 3 then p1 !! 3 - p2 !! 3 else 0
      c = 299792458.0
  in -(c * dt) * (c * dt) + dx*dx + dy*dy + dz*dz

-- | Classify interval
intervalType :: Double -> String
intervalType s
  | s < -1e-10 = "timelike"      -- Can be connected by massive particle
  | abs s < 1e-10 = "lightlike"  -- Light cone / null
  | otherwise = "spacelike"      -- Causally disconnected

-- ─────────────────────────────────────────────────────────────────────────────
-- Light Cones
-- ─────────────────────────────────────────────────────────────────────────────

-- | Future light cone boundary (null surface)
-- (cΔt)² = Δx² + Δy² + Δz²
futureLightConeBoundary :: Vector -> Double -> Double -> [Vector]
futureLightConeBoundary (Vector center) radius c =
  let angles = [0, pi/6 .. 2*pi]
      conePoints = [ Vector [t, radius * cos a, radius * sin a, 0]
                   | t <- [0, 0.1 .. 1]
                   , a <- angles
                   ]
  in conePoints

-- ─────────────────────────────────────────────────────────────────────────────
-- Gravitational Time Dilation (General Relativity)
-- ─────────────────────────────────────────────────────────────────────────────

-- | Create Schwarzschild metric field (around non-rotating black hole)
schwarzschildField :: Double -> Double -> RelativityField
schwarzschildField mass_kg rs = RelativityField
  { relativityFieldId = "schwarzschild-" ++ show mass_kg
  , relativityTimeDilation = \(Vector pos) ->
      let r = if length pos >= 3
              then sqrt (pos!!0*pos!!0 + pos!!1*pos!!1 + pos!!2*pos!!2)
              else 1e6
      in schwarzschildTimeDilation rs r 299792458.0
  , localSpeedOfLight = 299792458.0
  , gravitationalTimeWarp = \potential ->
      sqrt (max 0.0001 (1.0 + 2.0 * potential / (299792458.0 ^ 2)))
  , schwarzschildRadius = rs
  }

-- | Create weak-field (post-Newtonian) relativity field
weakFieldRelativity :: Double -> RelativityField
weakFieldRelativity phi0 = RelativityField
  { relativityFieldId = "weak-field"
  , relativityTimeDilation = \(Vector pos) ->
      let r = if length pos >= 3
              then sqrt (pos!!0*pos!!0 + pos!!1*pos!!1 + pos!!2*pos!!2)
              else 1e6
          phi = phi0 / r  -- Newtonian potential ∝ 1/r
      in 1.0 + phi / (299792458.0 ^ 2)  -- Post-Newtonian: g_tt ≈ -(1 + 2φ/c²)
  , localSpeedOfLight = 299792458.0
  , gravitationalTimeWarp = \pot -> 1.0 + pot / (299792458.0 ^ 2)
  , schwarzschildRadius = 0.0
  }

-- ─────────────────────────────────────────────────────────────────────────────
-- Redshift / Blueshift
-- ─────────────────────────────────────────────────────────────────────────────

-- | Gravitational redshift (Doppler-like due to time dilation)
-- ν_observer = ν_source * √(g_tt_observer / g_tt_source)
gravitationalRedshift :: RelativityField -> Vector -> Vector -> Double -> Double
gravitationalRedshift field posSource posObs freq =
  let dilationSource = relativityTimeDilation field posSource
      dilationObs = relativityTimeDilation field posObs
  in freq * sqrt (dilationObs / max 0.01 dilationSource)

-- ─────────────────────────────────────────────────────────────────────────────
-- WORM-sealed relativity observations
-- ─────────────────────────────────────────────────────────────────────────────

data RelativityObservation = RelativityObservation
  { relStep :: Int
  , relPosition :: Vector
  , relProperTime :: Double
  , relTimeDilation :: Double
  , relWormSeal :: String
  } deriving (Show, Generic)

-- | WORM seal observation
sealRelativityObservation :: Int -> Vector -> RelativityField -> RelativityObservation
sealRelativityObservation step pos field =
  let dilation = relativityTimeDilation field pos
      properTime = localProperTime field pos 0.0 1.0  -- Unit global time
      seal = "WORM[relativity:step=" ++ show step
             ++ ":pos=" ++ vectorToString pos
             ++ ":time_dilation=" ++ show (round (dilation * 10000) :: Integer)
             ++ "]"
  in RelativityObservation step pos properTime dilation seal

-- | Vector to string for sealing
vectorToString :: Vector -> String
vectorToString (Vector xs) = "[" ++ unwords (map (\x -> take 6 (show x)) xs) ++ "]"

-- ─────────────────────────────────────────────────────────────────────────────
-- Special Relativity Configuration
-- ─────────────────────────────────────────────────────────────────────────────

-- | Create special relativity field (flat spacetime)
specialRelativity :: RelativityField
specialRelativity = RelativityField
  { relativityFieldId = "special-relativity"
  , relativityTimeDilation = \_ -> 1.0  -- No gravity
  , localSpeedOfLight = 299792458.0
  , gravitationalTimeWarp = \_ -> 1.0
  , schwarzschildRadius = 0.0
  }

-- | Create near-Schwarzschild field (e.g., around Sun)
sunField :: RelativityField
sunField =
  let m_sun = 1.989e30  -- kg
      g = 6.674e-11
      c = 299792458.0
      rs = 2.0 * g * m_sun / (c * c)
  in schwarzschildField m_sun rs
