{-# LANGUAGE DeriveGeneric #-}

module ConsensusVoting
  ( castVote
  , consensusRound
  , detectConflict
  , resolveConflict
  , syncAgentStates
  , multiAgentVote
  , getConsensusObservations
  , aggregateVotesForObservation
  , updateWorldModelWithConsensus
  , anomalyScoring
  , conflictThreshold
  ) where

import ConsensusTypes
import qualified Data.Map as Map
import Data.Map (Map)
import Data.List (sortBy, groupBy, maximumBy, nub)
import Data.Ord (comparing, Down(..))
import GHC.Generics (Generic)

-- ─────────────────────────────────────────────────────────────────────────────
-- Consensus Parameters
-- ─────────────────────────────────────────────────────────────────────────────

-- | Threshold for declaring observations in conflict (normalized difference)
conflictThreshold :: Double
conflictThreshold = 0.25

-- | Minimum votes needed to form consensus
minVotesForConsensus :: Int
minVotesForConsensus = 2

-- | Consensus threshold (66%+)
consensusThreshold :: Double
consensusThreshold = 0.66

-- | Anomaly severity threshold (1-10 scale)
anomalySeverityThreshold :: Double
anomalySeverityThreshold = 0.5

-- ─────────────────────────────────────────────────────────────────────────────
-- Voting: Cast, Aggregate, Tally
-- ─────────────────────────────────────────────────────────────────────────────

-- | Cast a vote: voter agrees/disagrees with observation
castVote :: ConsensusState -> AgentId -> ObservationId -> Double -> Int -> ConsensusState
castVote state voterId obsId agreeScore round =
  let vote = makeVote voterId obsId agreeScore round 0
      newVotes = votes state ++ [vote]
  in state { votes = newVotes }

-- | Aggregate votes for single observation into consensus score
aggregateVotesForObservation :: ConsensusState -> ObservationId -> (Double, Int)
aggregateVotesForObservation state obsId =
  let obsVotes = votesForObservation (votes state) obsId
      voteCount = length obsVotes
  in if voteCount < minVotesForConsensus
     then (0.0, 0)
     else (consensusScore obsVotes, voteCount)

-- | Get all observations that reached consensus (66%+)
getConsensusObservations :: ConsensusState -> [Observation]
getConsensusObservations state =
  let allObs = observations state
  in filter (\obs -> let (score, count) = aggregateVotesForObservation state (obsId obs)
                     in count >= minVotesForConsensus && score > 0.33) allObs

-- ─────────────────────────────────────────────────────────────────────────────
-- Consensus Round: Observation → Voting → World Model Update
-- ─────────────────────────────────────────────────────────────────────────────

-- | Execute full consensus round: tally votes, detect conflicts, update world model
consensusRound :: ConsensusState -> [AgentId] -> Int -> ConsensusState
consensusRound state participatingAgents roundNum =
  let -- Step 1: Group observations by ObservationId
      obsGroups = groupObservationsById state

      -- Step 2: Compute consensus for each group
      consensusResults = map (\(obsId, obs) ->
        let (score, voteCount) = aggregateVotesForObservation state obsId
            vots = votesForObservation (votes state) obsId
        in (obsId, obs, score, voteCount, vots)
        ) obsGroups

      -- Step 3: Separate consensed vs. conflicted
      (consensusObs, conflictedObs) = partitionConsensus consensusResults

      -- Step 4: Detect conflicts
      detectedConflicts = detectConflictsBatch state conflictedObs

      -- Step 5: Resolve conflicts via majority vote
      resolvedObs = map (\(o, c) -> resolveConflictVia state o c) (zip conflictedObs detectedConflicts)

      -- Step 6: All observations that passed consensus filter
      finalConsensusObs = consensusObs ++ resolvedObs

      -- Step 7: Update world model
      updatedModel = updateWorldModelWithConsensus (worldModel state) finalConsensusObs state

      -- Step 8: Compute global confidence
      globalConf = if null finalConsensusObs
                   then confidence state
                   else averageDouble (map (\(_, _, s, _, _) -> s) consensusResults)

      -- Step 9: Create vote round record
      voteRound = VoteRound roundNum 0 (votes state) (observations state)

      -- Step 10: Increment generation
      newGen = generation state + 1

  in state
     { worldModel = updatedModel
     , confidence = globalConf
     , voteRounds = voteRounds state ++ [voteRound]
     , conflicts = conflicts state ++ detectedConflicts
     , generation = newGen
     }

-- | Group observations by ObservationId
groupObservationsById :: ConsensusState -> [(ObservationId, [Observation])]
groupObservationsById state =
  let grouped = groupBy (\o1 o2 -> obsId o1 == obsId o2)
                        (sortBy (comparing obsId) (observations state))
  in map (\g -> (obsId (head g), g)) grouped

-- | Partition consensus results into consensed vs. conflicted
partitionConsensus :: [(ObservationId, [Observation], Double, Int, [Vote])]
                   -> ([(ObservationId, [Observation], Double, Int, [Vote])],
                       [(ObservationId, [Observation], Double, Int, [Vote])])
partitionConsensus results =
  let isConflicted (_, _, score, count, _) =
        count >= minVotesForConsensus && score <= 0.33
  in (filter (not . isConflicted) results, filter isConflicted results)

-- ─────────────────────────────────────────────────────────────────────────────
-- Conflict Detection + Resolution
-- ─────────────────────────────────────────────────────────────────────────────

-- | Detect conflicts: two agents' measurements differ by > threshold
detectConflictsBatch :: ConsensusState
                     -> [(ObservationId, [Observation], Double, Int, [Vote])]
                     -> [Conflict]
detectConflictsBatch state conflictedGroups =
  map (\(obsId, obs, _, _, vots) ->
    let agents = map agentId obs
        measDiff = if length obs >= 2
                   then
                     let m1 = measurements (head obs)
                         m2 = measurements (obs !! 1)
                     in measurementDifference m1 m2
                   else 0.0
    in Conflict obsId (RegionId 0) agents measDiff False
  ) conflictedGroups

-- | Detect conflict between two observations
detectConflict :: Observation -> Observation -> Bool
detectConflict obs1 obs2 =
  let dist = measurementDifference (measurements obs1) (measurements obs2)
  in dist > conflictThreshold && vectorDistance (coordinates obs1) (coordinates obs2) < 0.1

-- | Resolve conflict by majority vote
resolveConflict :: ConsensusState -> Conflict -> Observation
resolveConflict state conflict =
  case filter (\o -> obsId o == conflictObsId conflict) (observations state) of
    [] -> error "Conflict references non-existent observation"
    (o:_) -> o

-- | Resolve conflict in batch
resolveConflictVia :: ConsensusState -> (ObservationId, [Observation], Double, Int, [Vote])
                   -> Conflict -> Observation
resolveConflictVia state (obsId, obs, _, _, votes) conflict =
  if null obs then error "resolveConflictVia: no observations in conflict group"
  else if null votes
       then head obs  -- No votes: return first observation
       else
         -- Find observation with highest average agreement
         let obsWithScores = [(o, averageDouble [agreement v | v <- votes, votedObsId v == obsId o]) | o <- obs]
         in if null obsWithScores
            then head obs  -- Fallback: no matching votes found
            else let (winningObs, _) = maximumBy (comparing snd) obsWithScores
                 in winningObs

-- ─────────────────────────────────────────────────────────────────────────────
-- Multi-Agent Voting
-- ─────────────────────────────────────────────────────────────────────────────

-- | All agents vote on a new observation from one agent
multiAgentVote :: ConsensusState -> Observation -> [AgentId] -> Int -> ConsensusState
multiAgentVote state newObs voterIds round =
  let -- Observation already added to state
      obsIdToVoteOn = obsId newObs

      -- Each agent compares against their own measurements in same region
      votes = concatMap (\voterId ->
        let otherObs = observationsByAgent (observations state) voterId
            -- If agent has measurements in same region, vote on similarity
            similarObs = filter (\o -> case (regionType newObs, regionType o) of
                                         (Just r1, Just r2) -> r1 == r2
                                         _ -> False) otherObs
        in if null similarObs
           then [makeVote voterId obsIdToVoteOn 0.0 round 0]  -- Uncertain
           else let avgDiff = averageDouble [measurementDifference (measurements newObs) (measurements o) | o <- similarObs]
                    agreeScore = 1.0 - min 1.0 (avgDiff / 0.5)  -- normalize to [-1, 1]
                in [makeVote voterId obsIdToVoteOn agreeScore round 0]
        ) voterIds

      newVotes = votes state ++ votes
  in state { votes = newVotes }

-- ─────────────────────────────────────────────────────────────────────────────
-- World Model Update
-- ─────────────────────────────────────────────────────────────────────────────

-- | Update world model with newly consensed observations
updateWorldModelWithConsensus :: WorldModel -> [Observation] -> ConsensusState -> WorldModel
updateWorldModelWithConsensus model consensusObs state =
  let -- Extract regions
      regionsFromObs = [(RegionId i, regionType o) | (i, o) <- zip [0..] consensusObs, regionType o /= Nothing]
      newRegionMap = Map.fromList [(rId, rt) | (rId, Just rt) <- regionsFromObs]

      -- Update agent positions (latest from consensus observations)
      newAgentPositions = Map.fromList [(agentId o, coordinates o) | o <- consensusObs]

      -- Detect anomalies
      detectedAnomalies = anomalyScoring state consensusObs

      -- Frontier regions (low confidence, high anomaly)
      frontierIds = [RegionId i | (i, _) <- zip [0..] consensusObs, any (\a -> anomalySeverity a > 0.6) detectedAnomalies]

      -- Extract confidence from observations
      obsConfidenceValues = map (\o -> o.confidence) consensusObs

  in WorldModel
     { regionTypes = Map.union newRegionMap (regionTypes model)
     , agentPositions = Map.union newAgentPositions (agentPositions model)
     , anomalies = anomalies model ++ detectedAnomalies
     , frontierRegions = nub (frontierRegions model ++ frontierIds)
     , modelConfidence = averageDouble obsConfidenceValues
     , modelGeneration = modelGeneration model + 1
     }

-- ─────────────────────────────────────────────────────────────────────────────
-- Anomaly Detection
-- ─────────────────────────────────────────────────────────────────────────────

-- | Score anomalies from consensus observations
anomalyScoring :: ConsensusState -> [Observation] -> [Anomaly]
anomalyScoring state consensusObs =
  let -- Find observations with high measurement variance
      highVarianceObs = filter (\o -> confidence o < 0.5) consensusObs

      -- Group by location
      locGroups = groupBy (\o1 o2 -> vectorDistance (coordinates o1) (coordinates o2) < 0.05)
                          (sortBy (comparing coordinates) highVarianceObs)

      -- Create anomalies
      anomalies = concatMap (\group ->
        if length group > 0
        then let avgLoc = Vector
                   (averageDouble (map (\o -> vx (coordinates o)) group))
                   (averageDouble (map (\o -> vy (coordinates o)) group))
                   (averageDouble (map (\o -> vz (coordinates o)) group))
                 agentSet = map agentId group
                 severity = 1.0 - averageDouble (map confidence group)
             in [Anomaly (length (anomalies state)) avgLoc severity 0 agentSet 0.5]
        else []
        ) locGroups
  in anomalies

-- ─────────────────────────────────────────────────────────────────────────────
-- State Synchronization
-- ─────────────────────────────────────────────────────────────────────────────

-- | Synchronize all agents to shared world model and confidence
syncAgentStates :: ConsensusState -> ConsensusState
syncAgentStates state =
  -- All agents converge to world model + global confidence
  -- This is a no-op in ConsensusState (agents are external)
  -- but signifies: all agents should now use state's worldModel + confidence
  state

-- ─────────────────────────────────────────────────────────────────────────────
-- Utility: Observation as a data type that can be updated
-- ─────────────────────────────────────────────────────────────────────────────

-- | Mark observation as WORM-sealed
sealObservation :: Observation -> Int -> Observation
sealObservation obs round = obs { wormSealed = True, sealRound = Just round }

-- | Seal all observations in consensus state
sealObservationsInRound :: ConsensusState -> Int -> ConsensusState
sealObservationsInRound state round =
  let sealedObs = map (\o -> sealObservation o round) (observations state)
  in state { observations = sealedObs }
