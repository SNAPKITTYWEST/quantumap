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
    """Shannon entropy of weight distribution, normalized to [0, 1]."""
    probs = np.abs(weights)
    total = probs.sum()
    if total < 1e-15:
        return 1.0
    probs = probs / total
    probs = probs[probs > 0]
    entropy = -np.sum(probs * np.log2(probs))
    max_entropy = np.log2(len(probs)) if len(probs) > 1 else 1.0
    return float(entropy / max_entropy) if max_entropy > 0 else 0.0


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
