{-# LANGUAGE DeriveGeneric #-}

module QuantumModule where

import ManifoldGeometry hiding (decoherenceRate)
import Data.List (nubBy)
import Data.Function (on)
import GHC.Generics (Generic)
import System.Random (RandomGen, StdGen, randomR, mkStdGen)

-- ─────────────────────────────────────────────────────────────────────────────
-- Quantum Superposition & Decoherence
-- ─────────────────────────────────────────────────────────────────────────────

-- | Complex number for quantum amplitudes
data Complex = Complex
  { realPart :: Double
  , imagPart :: Double
  } deriving (Show, Generic)

-- | Complex conjugate
complexConj :: Complex -> Complex
complexConj (Complex r i) = Complex r (-i)

-- | Complex magnitude
complexMag :: Complex -> Double
complexMag (Complex r i) = sqrt (r*r + i*i)

-- | Complex multiplication
complexMult :: Complex -> Complex -> Complex
complexMult (Complex r1 i1) (Complex r2 i2) =
  Complex (r1*r2 - i1*i2) (r1*i2 + i1*r2)

-- | Probability density |ψ|²
probabilityDensity :: Complex -> Double
probabilityDensity psi = (complexMag psi) ^ 2

-- ─────────────────────────────────────────────────────────────────────────────
-- Quantum Branches (Many-Worlds)
-- ─────────────────────────────────────────────────────────────────────────────

data QuantumBranch = QuantumBranch
  { branchId :: Int
  , branchLabel :: String
  , amplitude :: Complex
  , stateVector :: Vector
  , probability :: Double               -- Probability of this branch
  , decoherenceTime :: Double           -- When this branch becomes classical
  } deriving (Show, Generic)

-- ─────────────────────────────────────────────────────────────────────────────
-- Superposition State
-- ─────────────────────────────────────────────────────────────────────────────

data QuantumSuperposition = QuantumSuperposition
  { superpositionId :: String
  , branches :: [QuantumBranch]
  , collapseThreshold :: Double         -- Below this probability, branch dies
  , decoherenceRate :: Double           -- Rate of decoherence: dρ/dt = -Γρ
  , currentStep :: Int
  } deriving (Show, Generic)

-- | Normalize amplitudes (enforce Σ|ψ_i|² = 1)
normalizeAmplitudes :: [QuantumBranch] -> [QuantumBranch]
normalizeAmplitudes branches =
  let totalProb = sum [probabilityDensity (amplitude b) | b <- branches]
      normFactor = if totalProb > 0 then 1.0 / sqrt totalProb else 1.0
      renormalizedBranches = map (\b -> b
        { amplitude = let Complex r i = amplitude b
                      in Complex (r * normFactor) (i * normFactor)
        , probability = probabilityDensity (amplitude b)
        }) branches
  in renormalizedBranches

-- ─────────────────────────────────────────────────────────────────────────────
-- Wave Function Collapse (Measurement)
-- ─────────────────────────────────────────────────────────────────────────────

-- | Sample from superposition (non-deterministic collapse)
-- Probability of branch i = |ψ_i|²
sampleSuperposition :: StdGen -> QuantumSuperposition -> (QuantumBranch, StdGen)
sampleSuperposition gen qs =
  let normalized = normalizeAmplitudes (branches qs)
      probs = map probability normalized
      (r, gen') = randomR (0.0, 1.0) gen
      chosenBranch = selectByProbability r probs normalized
  in (chosenBranch, gen')

-- | Select branch based on cumulative probability
selectByProbability :: Double -> [Double] -> [QuantumBranch] -> QuantumBranch
selectByProbability r probs branches =
  go r 0 probs branches
  where
    go _ _ [] [] = error "No branches"
    go _ _ (_ : _) [] = error "Probability mismatch"
    go p cumProb (prob : probRest) (branch : branchRest)
      | p < cumProb + prob = branch
      | otherwise = go p (cumProb + prob) probRest branchRest
    go _ _ _ _ = error "Probability selection failed"

-- ─────────────────────────────────────────────────────────────────────────────
-- Branch Exploration (Without Collapse)
-- ─────────────────────────────────────────────────────────────────────────────

-- | Significant branches (keep if probability > threshold)
significantBranches :: QuantumSuperposition -> [QuantumBranch]
significantBranches qs =
  filter (\b -> probability b > collapseThreshold qs) (branches qs)

-- | Count live branches (non-negligible probability)
countLiveBranches :: QuantumSuperposition -> Int
countLiveBranches qs = length (significantBranches qs)

-- | Entanglement entropy (Shannon entropy of branch probabilities)
entanglementEntropy :: QuantumSuperposition -> Double
entanglementEntropy qs =
  let probs = map probability (branches qs)
      nonZeroProbs = filter (> 0.0001) probs
  in -(sum [p * log p | p <- nonZeroProbs])

-- ─────────────────────────────────────────────────────────────────────────────
-- Decoherence: Branch Pruning Over Time
-- ─────────────────────────────────────────────────────────────────────────────

-- | Apply decoherence for one time step
-- Branches with low probability decay exponentially
decoherence :: QuantumSuperposition -> Double -> QuantumSuperposition
decoherence qs dt =
  let decayedBranches = map (\b ->
        let oldProb = probability b
            decayFactor = exp (-(decoherenceRate qs) * dt)
            newProb = oldProb * decayFactor
            newAmplitude = let Complex r i = amplitude b
                               scaleFactor = sqrt decayFactor
                           in Complex (r * scaleFactor) (i * scaleFactor)
        in b { probability = newProb, amplitude = newAmplitude }
        ) (branches qs)
      -- Renormalize
      normalized = normalizeAmplitudes decayedBranches
      -- Remove dead branches
      alive = filter (\b -> probability b > collapseThreshold qs) normalized
  in qs { branches = alive, currentStep = currentStep qs + 1 }

-- ─────────────────────────────────────────────────────────────────────────────
-- Quantum Tunneling (Probabilistic State Transfer)
-- ─────────────────────────────────────────────────────────────────────────────

-- | Tunneling probability through barrier
-- P ∝ exp(-2κL) where κ = √(2m(V-E))/ℏ
tunnelingProbability :: Double -> Double -> Double -> Double
tunnelingProbability barrierHeight particleEnergy barrierWidth =
  let eff_mass = 9.109e-31  -- electron mass
      hbar = 1.054571817e-34
      v_diff = barrierHeight - particleEnergy
      kappa = if v_diff > 0
              then sqrt (2.0 * eff_mass * v_diff) / hbar
              else 0
      prob = exp (-2.0 * kappa * barrierWidth)
  in min 1.0 prob

-- | Stochastic tunnel attempt
attemptTunneling :: StdGen -> Vector -> Double -> IO (Vector, Bool)
attemptTunneling gen pos tunnelingProb = do
  let (r, _) = randomR (0.0, 1.0) gen
      didTunnel = r < tunnelingProb
      -- Tunnel to random nearby position
      newPos = if didTunnel
               then vectorAdd pos (Vector [sin r, cos r, 0])
               else pos
  return (newPos, didTunnel)

-- ─────────────────────────────────────────────────────────────────────────────
-- Quantum Superposition Evolution (Schrödinger-like)
-- ─────────────────────────────────────────────────────────────────────────────

-- | Apply unitary transformation to branches
-- U |ψ⟩ = e^(-iHt/ℏ) |ψ⟩
unitaryEvolution :: QuantumSuperposition -> Double -> QuantumSuperposition
unitaryEvolution qs dt =
  let evolved = map (\b ->
        let oldPhase = atan2 (imagPart (amplitude b)) (realPart (amplitude b))
            energyContribution = (fromIntegral (branchId b) :: Double) * dt  -- Dummy Hamiltonian
            newPhase = oldPhase + energyContribution
            mag = complexMag (amplitude b)
            newAmp = Complex (mag * cos newPhase) (mag * sin newPhase)
        in b { amplitude = newAmp }
        ) (branches qs)
  in qs { branches = normalizeAmplitudes evolved }

-- ─────────────────────────────────────────────────────────────────────────────
-- Quantum Region Configuration
-- ─────────────────────────────────────────────────────────────────────────────

-- | Helper to create quantum branch
makeBranch :: Int -> Int -> Vector -> QuantumBranch
makeBranch i numBranches center = QuantumBranch
  { branchId = i
  , branchLabel = "branch-" ++ show i
  , amplitude = Complex (1.0 / sqrt (fromIntegral numBranches)) 0.0
  , stateVector = vectorAdd center (Vector [sin (fromIntegral i), cos (fromIntegral i), 0])
  , probability = 1.0 / fromIntegral numBranches
  , decoherenceTime = 1.0 / fromIntegral (i + 1)
  }

-- | Initialize superposition in region
initializeSuperposition :: String -> Int -> Vector -> QuantumSuperposition
initializeSuperposition regionId numBranches center =
  let initialBranches = [makeBranch i numBranches center | i <- [0..numBranches-1]]
  in QuantumSuperposition
    { superpositionId = regionId
    , branches = initialBranches
    , collapseThreshold = 0.001
    , decoherenceRate = 0.1
    , currentStep = 0
    }

-- ─────────────────────────────────────────────────────────────────────────────
-- WORM-sealed quantum observations
-- ─────────────────────────────────────────────────────────────────────────────

data QuantumObservation = QuantumObservation
  { qStep :: Int
  , qBranchesAlive :: Int
  , qEntropy :: Double
  , qCollapsedBranch :: Int
  , qWormSeal :: String
  } deriving (Show, Generic)

-- | WORM seal observation
sealQuantumObservation :: Int -> QuantumSuperposition -> Int -> QuantumObservation
sealQuantumObservation step qs collapsedId =
  let numAlive = countLiveBranches qs
      entropy = entanglementEntropy qs
      seal = "WORM[quantum:step=" ++ show step
             ++ ":branches_alive=" ++ show numAlive
             ++ ":entropy=" ++ show (round (entropy * 100) :: Integer)
             ++ ":collapsed_branch=" ++ show collapsedId ++ "]"
  in QuantumObservation step numAlive entropy collapsedId seal

-- ─────────────────────────────────────────────────────────────────────────────
-- Bell Test Simulator (EPR pairs)
-- ─────────────────────────────────────────────────────────────────────────────

-- | Entangled pair state |Φ+⟩ = (|00⟩ + |11⟩)/√2
eprPairSuperposition :: QuantumSuperposition
eprPairSuperposition = QuantumSuperposition
  { superpositionId = "epr-pair"
  , branches =
    [ QuantumBranch
      { branchId = 0
      , branchLabel = "|00⟩"
      , amplitude = Complex (1.0 / sqrt 2.0) 0.0
      , stateVector = Vector [0, 0, 0]
      , probability = 0.5
      , decoherenceTime = 0.0
      }
    , QuantumBranch
      { branchId = 1
      , branchLabel = "|11⟩"
      , amplitude = Complex (1.0 / sqrt 2.0) 0.0
      , stateVector = Vector [1, 1, 0]
      , probability = 0.5
      , decoherenceTime = 0.0
      }
    ]
  , collapseThreshold = 0.001
  , decoherenceRate = 0.0  -- Perfect coherence for Bell test
  , currentStep = 0
  }
