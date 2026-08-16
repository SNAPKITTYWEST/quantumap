"""
Checkpoint processing: SafeTensors ingestion and weight selection.

Supports:
  - Synthetic checkpoint generation (demo mode)
  - Real safetensors file loading (requires safetensors package)
  - Deterministic weight selection (lexicographic order)
"""

import numpy as np
from pathlib import Path
from .sovereign_shift import Q, N_ACTIVE

HAS_SAFETENSORS = False
try:
    from safetensors.numpy import load_file, save_file
    HAS_SAFETENSORS = True
except ImportError:
    pass


def generate_synthetic(seed: int = 42, path: str = "llama3_demo.safetensors") -> str:
    """
    Generate synthetic Llama 3-like checkpoint for demo.
    1M parameters, deterministic from seed.
    """
    if not HAS_SAFETENSORS:
        raise ImportError("safetensors required: pip install safetensors")

    rng = np.random.default_rng(seed)

    weights = {
        "model.embed_tokens.weight": rng.normal(0, 0.02, (32000, 4)).astype(np.float32),
        "model.layers.0.self_attn.q_proj.weight": rng.normal(0, 0.02, (4096, 4)).astype(np.float32),
        "model.layers.0.self_attn.k_proj.weight": rng.normal(0, 0.02, (4096, 4)).astype(np.float32),
        "model.layers.0.self_attn.v_proj.weight": rng.normal(0, 0.02, (4096, 4)).astype(np.float32),
        "model.layers.0.self_attn.o_proj.weight": rng.normal(0, 0.02, (4096, 4)).astype(np.float32),
        "model.layers.0.mlp.gate_proj.weight": rng.normal(0, 0.02, (11008, 4)).astype(np.float32),
        "model.layers.0.mlp.up_proj.weight": rng.normal(0, 0.02, (11008, 4)).astype(np.float32),
        "model.layers.0.mlp.down_proj.weight": rng.normal(0, 0.02, (4096, 4)).astype(np.float32),
        "model.layers.0.input_layernorm.weight": np.ones(4096, dtype=np.float32),
        "lm_head.weight": rng.normal(0, 0.02, (32000, 4)).astype(np.float32),
    }

    # Inject controlled hallucinations (sparse large spikes)
    halluc_mask = rng.random(weights["model.layers.0.mlp.gate_proj.weight"].shape) < 0.001
    weights["model.layers.0.mlp.gate_proj.weight"][halluc_mask] += 10.0

    save_file(weights, path, metadata={"format": "pt", "generator": "quantumap"})
    return path


def load_checkpoint(path: str) -> dict:
    """
    Load safetensors checkpoint.
    Returns dict of {tensor_name: np.ndarray}.
    """
    if not HAS_SAFETENSORS:
        raise ImportError("safetensors required: pip install safetensors")
    return load_file(path)


def extract_weights_lexicographic(tensors: dict, max_weights: int = None) -> np.ndarray:
    """
    Extract weights in deterministic lexicographic order.
    Sort by tensor name, then flatten in row-major order.
    Returns 1D array of all weights (or first max_weights).
    """
    all_weights = []
    for name in sorted(tensors.keys()):
        flat = tensors[name].flatten()
        all_weights.append(flat)

    combined = np.concatenate(all_weights)

    if max_weights is not None and len(combined) > max_weights:
        combined = combined[:max_weights]

    return combined


def extract_weights_from_numpy(raw_weights: np.ndarray) -> np.ndarray:
    """Extract from raw numpy array (for demo mode without safetensors)."""
    return raw_weights.flatten()


def generate_demo_weights(seed: int = 42, n_weights: int = None) -> np.ndarray:
    """
    Generate demo weights without safetensors dependency.
    Deterministic from seed. Mimics Llama 3 weight distribution.
    """
    if n_weights is None:
        n_weights = Q * 4  # Enough for full fleet + selection

    rng = np.random.default_rng(seed)
    weights = rng.normal(0, 0.02, n_weights).astype(np.float64)

    # Inject hallucination spikes (0.1% of weights)
    n_halluc = max(1, int(n_weights * 0.001))
    halluc_idx = rng.choice(n_weights, size=n_halluc, replace=False)
    weights[halluc_idx] += rng.choice([-10.0, 10.0], size=n_halluc)

    return weights
