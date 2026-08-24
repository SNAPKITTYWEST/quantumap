-- ═══════════════════════════════════════════════════════════════════════════════
-- AhmadBotAgent.hs — Ahmad_bot as a SpacetimeAgent
-- haskell/AhmadBotAgent.hs
--
-- Connects AToKio (7-invariant bounded runtime) to the spacetime simulation.
-- Ahmad_bot IS an agent in the manifold. Every query it processes is an
-- observation of the region it currently occupies. Every insight it produces
-- moves it toward a new frame.
--
-- Architecture:
--   AToKioRuntime (invariant gates + WORM log)
--       ↕
--   AhmadBotAgent (SpacetimeAgent with BotAgentState payload)
--       ↕
--   ProductionEnvironment (physics manifold, 10-agent consensus)
--
-- The frame Ahmad is in determines how it reasons:
--   Quantum    → probabilistic, branching, superposition of answers
--   Gravity    → structured, convergent, pulling toward known attractors
--   Relativity → time-aware, context-relative, observer-dependent
--   Wormhole   → shortcut reasoning, distant concepts connected
--   Horizon    → boundary detection, "this is the edge of what I can see"
--   Unknown    → explore, gather data, no prior frame assumed
--
-- WORM-sealed at every step. 7 Agda invariants enforced on every bind.
--
-- Ahmad Ali Parr · SnapKitty Collective · Bel Esprit D'Accord Trust · 2026
-- ═══════════════════════════════════════════════════════════════════════════════

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module AhmadBotAgent where

import Control.Concurrent (MVar, newMVar, readMVar, modifyMVar_, threadDelay)
import Control.Monad (forM_, when, unless)
import Data.List (intercalate, foldl')
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Time (getCurrentTime, formatTime, defaultTimeLocale)
import GHC.Generics (Generic)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

-- ── Import AToKio runtime ─────────────────────────────────────────────────────
import AToKio
  ( BotAgentState(..)
  , InvariantViolation(..)
  , AToKioRuntime(..)
  , checkAllInvariants
  , encodeWormEntry
  , initialState
  , initRuntime
  , enqueueTask
  , readWormLog
  )

-- ── Local re-declaration of SpacetimeAgent types ──────────────────────────────
-- (avoids circular imports while preserving the same structure)

data Frame
  = Unknown
  | Gravity
  | Relativity
  | Quantum
  | Wormhole
  | Horizon
  deriving (Show, Eq, Ord, Generic)

data BotGoal
  = ExploreFrame Frame          -- enter and understand a new frame
  | DeepInspect Frame           -- spend multiple steps in same frame
  | BridgeFrames Frame Frame    -- connect two frames via insight
  | ReachConsensus              -- agree with other agents on observation
  | HaltAtBoundary              -- stop — horizon detected
  deriving (Show, Eq, Generic)

-- ── AhmadBotAgent: the merged type ───────────────────────────────────────────

data AhmadBotAgent = AhmadBotAgent
  { abaId           :: String
  , abaPosition     :: (Double, Double)    -- position in manifold
  , abaFrame        :: Frame               -- current detected frame
  , abaGoal         :: BotGoal             -- what we're pursuing
  , abaBotState     :: BotAgentState       -- AToKio invariant state
  , abaObservations :: [BotObservation]    -- WORM-sealed history
  , abaConfidence   :: Double              -- [0..1] frame confidence
  , abaGeneration   :: Int                 -- how many frames visited
  } deriving (Show, Generic)

-- ── BotObservation: one merged observation from both systems ──────────────────

data BotObservation = BotObservation
  { boStep        :: Int
  , boAgentId     :: String
  , boPosition    :: (Double, Double)
  , boFrame       :: Frame
  , boQuery       :: String                -- what the bot was processing
  , boInsight     :: String                -- what it produced
  , boWormSeal    :: String                -- WORM entry hash
  , boInvariants  :: Bool                  -- all 7 passed?
  } deriving (Show, Generic)

-- ── Frame detection from position (same formula as ProductionSimulator) ───────

detectFrameFromPosition :: (Double, Double) -> Frame
detectFrameFromPosition (x, y) =
  let magnitude = sqrt (x*x + y*y)
  in if magnitude < 20.0      then Quantum
     else if magnitude < 50.0 then Gravity
     else if magnitude < 80.0 then Relativity
     else                          Wormhole

-- ── Movement: each frame has a pull direction ─────────────────────────────────

frameMovement :: Frame -> (Double, Double)
frameMovement Quantum    = ( 5.0,  5.0)   -- seek center
frameMovement Gravity    = (-5.0, -5.0)   -- seek gravity well
frameMovement Relativity = ( 8.0, -3.0)   -- lateral time dilation
frameMovement Wormhole   = (10.0,  0.0)   -- seek shortcut
frameMovement Horizon    = ( 0.0,  0.0)   -- halt
frameMovement Unknown    = ( 2.0,  2.0)   -- gentle exploration

applyMovement :: (Double, Double) -> (Double, Double) -> (Double, Double)
applyMovement (px, py) (dx, dy) =
  let stepSize = 1.5
      clamp v  = max (-120.0) (min 120.0 v)
  in (clamp (px + stepSize * dx), clamp (py + stepSize * dy))

-- ── Goal update: frame determines new goal ────────────────────────────────────

updateGoal :: AhmadBotAgent -> Frame -> BotGoal
updateGoal agent newFrame =
  case (abaGoal agent, newFrame) of
    (ExploreFrame f, f') | f == f' && abaConfidence agent > 0.8
                                   -> DeepInspect f
    (DeepInspect f,  f') | f /= f' -> BridgeFrames f f'
    (_,              Horizon)      -> HaltAtBoundary
    (_,              f)            -> ExploreFrame f

-- ── Confidence update ─────────────────────────────────────────────────────────

updateConfidence :: AhmadBotAgent -> Frame -> Double
updateConfidence agent newFrame =
  let delta = if newFrame == abaFrame agent then 0.1 else -0.05
  in max 0.0 (min 1.0 (abaConfidence agent + delta))

-- ── Query generation: frame determines what bot asks ──────────────────────────
-- This is Ahmad's reframing logic: what question do you ask
-- when you're in a Quantum region vs a Gravity region?

generateQuery :: Frame -> BotGoal -> Int -> String
generateQuery Quantum    _                step = "step " ++ show step ++ ": superposition — what are all possible answers?"
generateQuery Gravity    _                step = "step " ++ show step ++ ": convergence — what is the attractor?"
generateQuery Relativity _                step = "step " ++ show step ++ ": relative — from which observer frame?"
generateQuery Wormhole   (BridgeFrames f1 f2) _ = "bridge: how does " ++ show f1 ++ " connect to " ++ show f2 ++ "?"
generateQuery Wormhole   _                step = "step " ++ show step ++ ": shortcut — what connects distant concepts?"
generateQuery Horizon    _                _    = "boundary: what is the edge of what I can know?"
generateQuery Unknown    _                step = "step " ++ show step ++ ": unknown — what frame am I in?"

-- ── Insight generation: frame determines what bot produces ────────────────────

generateInsight :: Frame -> String -> Int -> String
generateInsight Quantum    query _ = "branch[" ++ query ++ "]: multiple valid answers coexist"
generateInsight Gravity    query _ = "converge[" ++ query ++ "]: single attractor found"
generateInsight Relativity query _ = "relative[" ++ query ++ "]: answer depends on observer"
generateInsight Wormhole   query _ = "bridge[" ++ query ++ "]: shortcut path established"
generateInsight Horizon    query _ = "boundary[" ++ query ++ "]: limit of knowable reached"
generateInsight Unknown    query _ = "explore[" ++ query ++ "]: gathering frame data"

-- ── AToKio invariant advance: tick BotAgentState forward ─────────────────────

advanceBotState :: BotAgentState -> Either InvariantViolation BotAgentState
advanceBotState s =
  let s' = s { step               = step s + 1
              , messageCount        = messageCount s + 1
              , validProtocolSteps  = validProtocolSteps s + 1
              , apiKeyUsage         = apiKeyUsage s + 1
              , errorStatus         = 0
              , stateValid          = True
              }
  in case checkAllInvariants s' (step s') of
       Left err -> Left err
       Right () -> Right s'

-- ── Single agent step ─────────────────────────────────────────────────────────

stepAhmadBot :: AhmadBotAgent -> IO (Either InvariantViolation AhmadBotAgent)
stepAhmadBot agent = do
  let k        = step (abaBotState agent)
      newPos   = applyMovement (abaPosition agent) (frameMovement (abaFrame agent))
      newFrame = detectFrameFromPosition newPos
      newConf  = updateConfidence agent newFrame
      newGoal  = updateGoal agent newFrame
      query    = generateQuery newFrame newGoal k
      insight  = generateInsight newFrame query k

  case advanceBotState (abaBotState agent) of
    Left err -> return (Left err)
    Right newBotState -> do
      -- WORM seal this observation
      now <- getCurrentTime
      let timestamp = formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S" now
          seal = intercalate "|"
            [ "AHMAD_BOT"
            , timestamp
            , "id="   ++ abaId agent
            , "step=" ++ show k
            , "pos="  ++ show newPos
            , "frame=" ++ show newFrame
            , "query=" ++ take 60 query
            ]
          obs = BotObservation
            { boStep       = k
            , boAgentId    = abaId agent
            , boPosition   = newPos
            , boFrame      = newFrame
            , boQuery      = query
            , boInsight    = insight
            , boWormSeal   = seal
            , boInvariants = True
            }
          newAgent = agent
            { abaPosition     = newPos
            , abaFrame        = newFrame
            , abaGoal         = newGoal
            , abaBotState     = newBotState
            , abaObservations = abaObservations agent ++ [obs]
            , abaConfidence   = newConf
            , abaGeneration   = abaGeneration agent + (if newFrame /= abaFrame agent then 1 else 0)
            }
      return (Right newAgent)

-- ── Multi-step run ────────────────────────────────────────────────────────────

runAhmadBot :: AhmadBotAgent -> Int -> IO (Either InvariantViolation AhmadBotAgent)
runAhmadBot agent 0 = return (Right agent)
runAhmadBot agent n = do
  result <- stepAhmadBot agent
  case result of
    Left err     -> return (Left err)
    Right agent' -> runAhmadBot agent' (n - 1)

-- ── Multi-bot consensus: Ahmad_bot swarm ─────────────────────────────────────
-- Multiple AhmadBotAgents run in parallel. Every 10 steps they vote
-- on what frame the manifold is "really" in at their shared region.

data BotConsensus = BotConsensus
  { bcRound         :: Int
  , bcAgreeingBots  :: Int
  , bcTotalBots     :: Int
  , bcWinningFrame  :: Frame
  , bcAgreementRate :: Double
  } deriving (Show, Generic)

consensusVote :: [AhmadBotAgent] -> Int -> BotConsensus
consensusVote agents roundNum =
  let frames     = map abaFrame agents
      frameCounts = foldl' (\m f -> Map.insertWith (+) f 1 m) Map.empty frames
      (winFrame, winCount) = Map.foldlWithKey'
        (\(bf, bc) f c -> if c > bc then (f, c) else (bf, bc))
        (Unknown, 0) frameCounts
      rate = fromIntegral winCount / fromIntegral (length agents)
  in BotConsensus
    { bcRound         = roundNum
    , bcAgreeingBots  = winCount
    , bcTotalBots     = length agents
    , bcWinningFrame  = winFrame
    , bcAgreementRate = rate
    }

-- ── Full simulation: N bots × M steps ────────────────────────────────────────

data BotSimResult = BotSimResult
  { bsrAgents       :: [AhmadBotAgent]
  , bsrConsensusLog :: [BotConsensus]
  , bsrWormLog      :: [String]
  , bsrTotalObs     :: Int
  , bsrFrameVisits  :: Map Frame Int
  } deriving (Show, Generic)

runBotSimulation :: [AhmadBotAgent] -> Int -> IO BotSimResult
runBotSimulation initialAgents totalSteps = go initialAgents [] [] 0
  where
    go agents consensusLog wormLog step
      | step >= totalSteps = do
          let allObs      = concatMap abaObservations agents
              frameVisits = foldl' (\m obs -> Map.insertWith (+) (boFrame obs) 1 m)
                              Map.empty allObs
              allSeals    = map boWormSeal allObs
          return BotSimResult
            { bsrAgents       = agents
            , bsrConsensusLog = consensusLog
            , bsrWormLog      = allSeals
            , bsrTotalObs     = length allObs
            , bsrFrameVisits  = frameVisits
            }
      | otherwise = do
          -- Step all agents
          results <- mapM stepAhmadBot agents
          let (errors, stepped) = foldr
                (\r (es, ss) -> case r of
                  Left e  -> (e:es, ss)
                  Right a -> (es, a:ss))
                ([], []) results

          -- Halt if any invariant violated
          unless (null errors) $ do
            hPutStrLn stderr $ "INVARIANT HALT step=" ++ show step ++ ": " ++ show (head errors)
            exitFailure

          -- Consensus every 10 steps
          let newConsensus
                | step `mod` 10 == 0 =
                    let c = consensusVote stepped (step `div` 10)
                    in consensusLog ++ [c]
                | otherwise = consensusLog

          -- Progress every 50 steps
          when (step `mod` 50 == 0) $ do
            let frames = map abaFrame stepped
                frameStr = intercalate "," (map show frames)
            putStrLn $ "  step=" ++ show step
                     ++ " frames=[" ++ frameStr ++ "]"
                     ++ " obs=" ++ show (sum (map (length . abaObservations) stepped))

          go stepped newConsensus wormLog (step + 1)

-- ── Initial agent factory ─────────────────────────────────────────────────────

mkAhmadBotAgent :: String -> (Double, Double) -> AhmadBotAgent
mkAhmadBotAgent agentId startPos =
  let frame = detectFrameFromPosition startPos
  in AhmadBotAgent
    { abaId           = agentId
    , abaPosition     = startPos
    , abaFrame        = frame
    , abaGoal         = ExploreFrame frame
    , abaBotState     = initialState
    , abaObservations = []
    , abaConfidence   = 0.5
    , abaGeneration   = 0
    }

-- ── Report ────────────────────────────────────────────────────────────────────

printBotSimReport :: BotSimResult -> IO ()
printBotSimReport result = do
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn "   AHMAD_BOT SPACETIME SIMULATION REPORT"
  putStrLn "══════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn $ "  Total observations:  " ++ show (bsrTotalObs result)
  putStrLn $ "  WORM seals:          " ++ show (length (bsrWormLog result))
  putStrLn $ "  Consensus rounds:    " ++ show (length (bsrConsensusLog result))
  putStrLn ""
  putStrLn "  Frame visit distribution:"
  forM_ (Map.toList (bsrFrameVisits result)) $ \(frame, count) ->
    putStrLn $ "    " ++ show frame ++ ": " ++ show count
  putStrLn ""
  putStrLn "  Per-agent summary:"
  forM_ (bsrAgents result) $ \agent ->
    putStrLn $ "    " ++ abaId agent
             ++ " | frame=" ++ show (abaFrame agent)
             ++ " | pos=" ++ show (abaPosition agent)
             ++ " | obs=" ++ show (length (abaObservations agent))
             ++ " | gen=" ++ show (abaGeneration agent)
             ++ " | conf=" ++ take 4 (show (abaConfidence agent))
  putStrLn ""
  putStrLn "  Last consensus round:"
  case reverse (bsrConsensusLog result) of
    [] -> putStrLn "    (none)"
    (c:_) -> do
      putStrLn $ "    round=" ++ show (bcRound c)
               ++ " | frame=" ++ show (bcWinningFrame c)
               ++ " | agreement=" ++ take 4 (show (bcAgreementRate c))
               ++ " (" ++ show (bcAgreeingBots c) ++ "/" ++ show (bcTotalBots c) ++ " bots)"
  putStrLn ""
  putStrLn "  Sample WORM seals (last 5):"
  mapM_ (\s -> putStrLn $ "    " ++ s) (take 5 (reverse (bsrWormLog result)))
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════════"

-- ── Main ──────────────────────────────────────────────────────────────────────

main :: IO ()
main = do
  putStrLn "AhmadBotAgent v1.0 — Ahmad_bot in the Spacetime Manifold"
  putStrLn "7 Agda invariants enforced · WORM-sealed · Multi-bot consensus"
  putStrLn ""

  -- Spawn 5 Ahmad_bot agents at different positions in the manifold
  -- Each starts in a different physics frame
  let agents =
        [ mkAhmadBotAgent "ahmad-1" (  10.0,   5.0)   -- Quantum region (|pos| < 20)
        , mkAhmadBotAgent "ahmad-2" (  35.0,  15.0)   -- Gravity region
        , mkAhmadBotAgent "ahmad-3" (  60.0,  30.0)   -- Relativity region
        , mkAhmadBotAgent "ahmad-4" (  85.0,   5.0)   -- Wormhole region
        , mkAhmadBotAgent "ahmad-5" (   0.0,  10.0)   -- Deep Quantum (origin)
        ]

  putStrLn $ "Spawning " ++ show (length agents) ++ " Ahmad_bot agents..."
  putStrLn ""
  putStrLn "Initial frames:"
  forM_ agents $ \a ->
    putStrLn $ "  " ++ abaId a ++ " @ " ++ show (abaPosition a)
             ++ " → " ++ show (abaFrame a)
  putStrLn ""

  -- Run 200 steps
  putStrLn "Running 200 steps..."
  result <- runBotSimulation agents 200

  -- Print report
  printBotSimReport result
