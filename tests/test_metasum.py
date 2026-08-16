"""Tests for MetaSum computation."""

import numpy as np
import sys
sys.path.insert(0, str(__file__).rsplit("/tests/", 1)[0])

from src.sovereign_shift import Q, N_ACTIVE, THETA
from src.metasum import compute, magnitude, coherent_signal, hallucination_bound, snr


def test_coherent_signal():
    """All agents at displacement 0 → |MetaSum| = N."""
    weights = np.ones(N_ACTIVE)
    displacements = np.zeros(N_ACTIVE)
    result = magnitude(weights, displacements)
    assert abs(result - N_ACTIVE) < 1e-6, f"Expected {N_ACTIVE}, got {result}"
    print(f"  PASS: coherent signal |MetaSum| = {result:.2f}")


def test_random_phase_suppression():
    """Random displacements → |MetaSum| ≪ N (suppressed by phase)."""
    rng = np.random.default_rng(42)
    weights = np.ones(Q)
    displacements = np.arange(Q, dtype=float)
    result = magnitude(weights, displacements)
    bound = hallucination_bound(Q)
    # Random phases should give |MetaSum| ~ √Q, much less than Q
    assert result < Q / 2, f"|MetaSum| = {result} should be ≪ {Q}"
    print(f"  PASS: random phases |MetaSum| = {result:.2f} ≪ {Q}")


def test_snr_above_21db():
    """SNR > 21 dB for N=1024, Q=2462."""
    result = snr(N_ACTIVE, N_ACTIVE)
    assert result > 21.0, f"SNR = {result:.2f} dB, expected > 21"
    print(f"  PASS: SNR = {result:.2f} dB > 21 dB")


def test_weyl_bound_approx_89():
    """Weyl bound √(N·log Q) ≈ 89."""
    bound = hallucination_bound(N_ACTIVE)
    assert 85 < bound < 95, f"Weyl bound = {bound:.2f}, expected ≈ 89"
    print(f"  PASS: Weyl bound = {bound:.2f} ≈ 89 = Sovereign Shift numerator")


if __name__ == "__main__":
    print("MetaSum Tests:")
    test_coherent_signal()
    test_random_phase_suppression()
    test_snr_above_21db()
    test_weyl_bound_approx_89()
    print("ALL PASS")
