"""
MetaSum: Phase-Weighted Direct Sum

⊕_M S = Σ w_i · exp(2πi · θ · d_i)

The categorical colimit of tensor-weight distributions aligned by
the Sovereign Shift θ = 89/2462.

True signal (aligned): |MetaSum| = N = 1024
Hallucination (random): |MetaSum| ≲ √(N·log Q) ≈ 89
SNR: > 21 dB
"""

import numpy as np
import math
from .sovereign_shift import THETA, Q, N_ACTIVE


def compute(weights: np.ndarray, displacements: np.ndarray) -> complex:
    """
    MetaSum = Σ w_i · exp(2πi · θ · d_i)

    Args:
        weights: Boolean states from BooleanAdapter
        displacements: Lateral positions (agent indices)

    Returns:
        Complex MetaSum value
    """
    phases = np.exp(2j * np.pi * THETA * displacements)
    return complex(np.sum(weights * phases))


def magnitude(weights: np.ndarray, displacements: np.ndarray) -> float:
    """|MetaSum| — the signal strength."""
    return abs(compute(weights, displacements))


def coherent_signal(n: int = N_ACTIVE) -> float:
    """Expected |MetaSum| for perfectly phase-aligned signal."""
    return float(n)


def hallucination_bound(n_halluc: int) -> float:
    """Weyl estimate: max |MetaSum| from n_halluc random-phase agents."""
    if n_halluc <= 0:
        return 0.0
    return math.sqrt(n_halluc * math.log(Q))


def snr(n_signal: int = N_ACTIVE, n_halluc: int = N_ACTIVE) -> float:
    """Signal-to-noise ratio in dB."""
    signal = coherent_signal(n_signal)
    noise = hallucination_bound(n_halluc)
    if noise < 1e-15:
        return float('inf')
    return 20 * math.log10(signal / noise)
