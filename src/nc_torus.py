"""
Non-Commutative Torus T²_{89/2462}: Explicit Matrix Representation

U (Clock): diagonal phase rotation, U_kk = ω^k
V (Shift): cyclic permutation, V|k⟩ = |k+1 mod Q⟩
Weyl relation: VU = ω UV where ω = exp(2πi × 89/2462)
"""

import numpy as np
from .sovereign_shift import THETA_NUM, THETA_DEN, Q, THETA


def clock_matrix(q: int = Q, p: int = THETA_NUM) -> np.ndarray:
    """U (Scaling Flow): q×q diagonal with U_kk = exp(2πi·p·k/q)."""
    omega = np.exp(2j * np.pi * p / q)
    return np.diag([omega**k for k in range(q)])


def shift_matrix(q: int = Q) -> np.ndarray:
    """V (Lateral Displacement): q×q cyclic shift."""
    V = np.zeros((q, q), dtype=complex)
    for k in range(q - 1):
        V[k + 1, k] = 1.0
    V[0, q - 1] = 1.0
    return V


def verify_weyl(U: np.ndarray, V: np.ndarray, q: int = Q, p: int = THETA_NUM) -> float:
    """Verify VU = exp(2πiθ) UV. Returns error norm."""
    omega = np.exp(2j * np.pi * p / q)
    return float(np.linalg.norm(V @ U - omega * (U @ V)))


def verify_periods(U: np.ndarray, V: np.ndarray, q: int = Q) -> tuple:
    """Verify V^q = I and U^q = I."""
    I = np.eye(q, dtype=complex)
    v_err = float(np.linalg.norm(np.linalg.matrix_power(V, q) - I))
    u_err = float(np.linalg.norm(np.linalg.matrix_power(U, q) - I))
    return v_err, u_err
