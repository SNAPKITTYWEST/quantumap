"""
BooleanAdapter: Neural weights → {-1, +1} boolean states.

Deterministic threshold: w > 0 → +1, w ≤ 0 → -1
No entropy-increasing randomness.
"""

import numpy as np


def adapt(weights: np.ndarray) -> np.ndarray:
    """Convert raw neural weights to boolean states {-1, +1}."""
    return np.where(weights > 0, 1.0, -1.0)


def adapt_with_threshold(weights: np.ndarray, threshold: float = 0.0) -> np.ndarray:
    """Convert with custom threshold."""
    return np.where(weights > threshold, 1.0, -1.0)


def select_active(bool_weights: np.ndarray, n_active: int) -> np.ndarray:
    """Select top n_active agents by absolute weight magnitude."""
    indices = np.argsort(np.abs(bool_weights))[::-1][:n_active]
    result = np.zeros_like(bool_weights)
    result[indices] = bool_weights[indices]
    return result
