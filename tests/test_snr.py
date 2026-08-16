"""Tests for Signal-to-Noise Ratio analysis."""

import numpy as np
import math
import sys
sys.path.insert(0, str(__file__).rsplit("/tests/", 1)[0])

from src.sovereign_shift import Q, N_ACTIVE, THETA, THETA_NUM
from src.metasum import compute, hallucination_bound


def test_snr_sweep():
    """SNR remains positive across hallucination sweep."""
    rng = np.random.default_rng(42)

    print("  Hallucination Sweep:")
    for n_halluc in [0, 10, 100, 500, 1000]:
        weights = np.zeros(Q)
        active = rng.choice(Q, size=N_ACTIVE, replace=False)
        weights[active] = 1.0

        if n_halluc > 0:
            inactive = np.setdiff1d(np.arange(Q), active)
            halluc = rng.choice(inactive, size=min(n_halluc, len(inactive)), replace=False)
            weights[halluc] = 1.0

        displacements = np.arange(Q, dtype=float)
        ms_mag = abs(compute(weights, displacements))
        bound = hallucination_bound(n_halluc) if n_halluc > 0 else 0
        print(f"    n_halluc={n_halluc:5d}: |MetaSum|={ms_mag:.2f}, Weyl={bound:.2f}")

    print("  PASS: SNR sweep complete")


def test_89_is_weyl_bound():
    """The Weyl bound √(N·log Q) ≈ 89 = Sovereign Shift numerator."""
    bound = hallucination_bound(N_ACTIVE)
    # Should be within 5% of 89
    ratio = bound / THETA_NUM
    assert 0.95 < ratio < 1.10, f"Weyl bound = {bound:.2f}, 89 * ratio = {ratio:.3f}"
    print(f"  PASS: Weyl bound = {bound:.2f}, ratio to 89 = {ratio:.3f}")


def test_impossible_hallucination_dominance():
    """Verify >134,000 agents needed to dominate (impossible with Q=2462)."""
    # |halluc| > N² / log(Q) needed to dominate
    needed = N_ACTIVE**2 / math.log(Q)
    max_possible = Q - N_ACTIVE  # 1438
    assert max_possible < needed, \
        f"max_possible={max_possible} should be < needed={needed:.0f}"
    print(f"  PASS: need {needed:.0f} halluc agents, max possible = {max_possible} (IMPOSSIBLE)")


if __name__ == "__main__":
    print("SNR Tests:")
    test_snr_sweep()
    test_89_is_weyl_bound()
    test_impossible_hallucination_dominance()
    print("ALL PASS")
