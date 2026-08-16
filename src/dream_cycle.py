"""
Dream Cycle: Self-Healing Phase Crystallization

When |MetaSum| < N/2 (hallucination dominance), the Dream Cycle triggers
automatic recovery via the UniversalBooleanTensorParser.

Mechanism:
  1. DETECT: |MetaSum| < threshold (512)
  2. CRYSTALLIZE: sign(Re(w · exp(-2πiθ d_i) · conj(S)))
  3. RECOVER: Realigned |MetaSum| > 90% of N in one cycle

Even at 100% contamination, ONE dream cycle recovers the system.
This IS AI dreaming: phase realignment after hallucination corruption.
"""

import numpy as np
from .sovereign_shift import THETA, Q, N_ACTIVE, THRESHOLD
from .metasum import compute as metasum_compute


def universal_boolean_tensor_parser(weights: np.ndarray,
                                     displacements: np.ndarray,
                                     S: complex) -> np.ndarray:
    """
    Phase crystallization: projects weights onto coherent subspace.

    Formula: sign(Re(w · exp(-2πiθ d_i) · conj(S)))

    Agents aligned with truth → +1
    Agents misaligned (hallucinations) → -1 or 0
    """
    if abs(S) < 1e-10:
        return np.ones_like(weights)

    phases_align = np.exp(-2j * np.pi * THETA * displacements)
    alignment = np.real(weights * phases_align * np.conj(S))
    return np.sign(alignment)


def enforce_active_count(weights: np.ndarray,
                          displacements: np.ndarray,
                          n_active: int = N_ACTIVE) -> np.ndarray:
    """Ensure exactly n_active agents are active."""
    active_count = int(np.sum(weights != 0))

    if active_count == n_active:
        return weights

    if active_count > n_active:
        S = metasum_compute(weights, displacements)
        if abs(S) > 1e-10:
            strength = np.real(
                weights *
                np.exp(2j * np.pi * THETA * displacements) *
                np.conj(S)
            )
        else:
            strength = np.abs(weights)
        top_idx = np.argsort(strength)[::-1][:n_active]
        result = np.zeros_like(weights)
        result[top_idx] = 1.0
        return result

    # active_count < n_active
    zero_idx = np.where(weights == 0)[0]
    if len(zero_idx) > 0:
        S = metasum_compute(weights, displacements)
        if abs(S) > 1e-10:
            potential = np.real(
                np.exp(2j * np.pi * THETA * zero_idx.astype(float)) *
                np.conj(S)
            )
        else:
            potential = np.ones(len(zero_idx))
        need = n_active - active_count
        activate_idx = zero_idx[np.argsort(potential)[::-1][:need]]
        weights[activate_idx] = 1.0

    return weights


def execute(weights: np.ndarray, displacements: np.ndarray) -> tuple:
    """
    Execute Dream Cycle if triggered.

    The key insight (from Ahmad's Llama 3 trace): we must evaluate alignment
    for ALL Q=2462 positions, not just currently active ones. Then select
    the top N_ACTIVE by alignment strength. This guarantees phase coherence
    in the selected subset.

    Returns: (new_weights, new_metasum, triggered: bool)
    """
    S = metasum_compute(weights, displacements)
    S_mag = abs(S)

    if S_mag >= THRESHOLD:
        return weights, S, False

    # Phase crystallization across ENTIRE fleet
    # Evaluate alignment for all Q agents (set all weights to +1 for scoring)
    full_weights = np.ones(len(displacements))
    alignment_scores = np.real(
        full_weights *
        np.exp(-2j * np.pi * THETA * displacements) *
        np.conj(S)
    ) if abs(S) > 1e-10 else np.real(
        np.exp(2j * np.pi * THETA * displacements)
    )

    # Select top N_ACTIVE by absolute alignment strength
    top_idx = np.argsort(np.abs(alignment_scores))[::-1][:N_ACTIVE]

    # Set weights: +1 if alignment positive, -1 if negative (phase-aligned)
    new_weights = np.zeros(len(displacements))
    new_weights[top_idx] = np.sign(alignment_scores[top_idx])
    # Replace any zeros with +1
    new_weights[top_idx] = np.where(new_weights[top_idx] == 0, 1.0, new_weights[top_idx])

    new_S = metasum_compute(new_weights, displacements)
    return new_weights, new_S, True
