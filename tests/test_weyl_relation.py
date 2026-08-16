"""Tests for Non-Commutative Torus Weyl relation."""

import numpy as np
import sys
sys.path.insert(0, str(__file__).rsplit("/tests/", 1)[0])

from src.sovereign_shift import THETA_NUM, THETA_DEN
from src.nc_torus import clock_matrix, shift_matrix, verify_weyl, verify_periods


def test_weyl_relation_small():
    """VU = ωUV for q=89 (manageable size)."""
    q = 89
    U = clock_matrix(q, THETA_NUM)
    V = shift_matrix(q)
    err = verify_weyl(U, V, q, THETA_NUM)
    assert err < 1e-10, f"Weyl relation error: {err}"
    print(f"  PASS: VU = ωUV (q={q}, error={err:.2e})")


def test_periods_small():
    """V^q = I and U^q = I for q=89."""
    q = 89
    U = clock_matrix(q, THETA_NUM)
    V = shift_matrix(q)
    v_err, u_err = verify_periods(U, V, q)
    assert v_err < 1e-10, f"V^q ≠ I: error={v_err}"
    assert u_err < 1e-10, f"U^q ≠ I: error={u_err}"
    print(f"  PASS: V^{q} = I (error={v_err:.2e}), U^{q} = I (error={u_err:.2e})")


def test_trace_shift_power():
    """Tr(V^k) = q if q|k, else 0."""
    q = 89
    V = shift_matrix(q)
    I = np.eye(q, dtype=complex)

    # V^q = I → Tr = q
    Vq = np.linalg.matrix_power(V, q)
    assert abs(np.trace(Vq) - q) < 1e-10

    # V^1 → Tr = 0 (no fixed points)
    assert abs(np.trace(V)) < 1e-10

    # V^(q//2) → Tr = 0 (89 is prime, no divisors)
    V_half = np.linalg.matrix_power(V, q // 2)
    assert abs(np.trace(V_half)) < 1e-10

    print(f"  PASS: Tr(V^k) = {q} if {q}|k, else 0")


def test_coprimality():
    """gcd(89, 2462) = 1."""
    from src.sovereign_shift import gcd
    assert gcd(THETA_NUM, THETA_DEN) == 1
    print(f"  PASS: gcd({THETA_NUM}, {THETA_DEN}) = 1")


if __name__ == "__main__":
    print("Weyl Relation Tests:")
    test_weyl_relation_small()
    test_periods_small()
    test_trace_shift_power()
    test_coprimality()
    print("ALL PASS")
