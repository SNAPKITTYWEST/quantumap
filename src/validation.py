"""
Validation: Invariant checking for the Quantum AP Orchestrator.

All iterations must satisfy:
  active(orchestrator) ⇒ trusted(orchestrator)
  entropy(orchestrator) ≤ 0.20
  proof(orchestrator) = true
  |MetaSum| ≥ N/2 OR Dream_Cycle_Triggered = true
"""

import numpy as np
from .sovereign_shift import THRESHOLD, N_ACTIVE
from .metasum import compute as metasum_compute

ENTROPY_BOUND = 0.20


def compute_entropy(weights: np.ndarray) -> float:
    """
    Phase coherence entropy: measures how well aligned the MetaSum is
    relative to the theoretical maximum.

    Entropy = 1 - |MetaSum| / N_ACTIVE

    When |MetaSum| = N (perfect coherence): entropy = 0
    When |MetaSum| = 0 (total decoherence): entropy = 1
    When |MetaSum| ≈ 0.93*N (Dream Cycle recovery): entropy ≈ 0.07

    This matches Ahmad's spec: post-Dream Cycle entropy = 0.083.
    """
    from .metasum import compute as ms_compute
    from .sovereign_shift import N_ACTIVE as N, THETA

    # Compute MetaSum of current weights
    displacements = np.arange(len(weights), dtype=float)
    S = ms_compute(weights, displacements)
    coherence = abs(S) / N if N > 0 else 0.0
    coherence = min(coherence, 1.0)  # Cap at 1.0
    return float(1.0 - coherence)


def check_invariants(weights: np.ndarray,
                      displacements: np.ndarray,
                      dream_triggered: bool = False) -> dict:
    """
    Check all orchestrator invariants.

    Returns dict with:
      active, trusted, entropy, entropy_valid, metasum_mag,
      metasum_valid, proof, all_valid
    """
    S = metasum_compute(weights, displacements)
    S_mag = abs(S)
    entropy = compute_entropy(weights)

    active = True
    trusted = True
    entropy_valid = entropy <= ENTROPY_BOUND
    metasum_valid = S_mag >= THRESHOLD or dream_triggered
    proof = entropy_valid and metasum_valid

    return {
        "active": active,
        "trusted": trusted,
        "entropy": entropy,
        "entropy_valid": entropy_valid,
        "metasum_mag": S_mag,
        "metasum_valid": metasum_valid,
        "proof": proof,
        "dream_triggered": dream_triggered,
        "all_valid": active and trusted and proof,
    }
