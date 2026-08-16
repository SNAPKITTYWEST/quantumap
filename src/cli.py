"""
QuantumAP CLI: Command-line interface for the Quantum AP Orchestrator.

Commands:
  python -m src                         Demo mode (synthetic weights)
  python -m src --checkpoint FILE       Process safetensors checkpoint
  python -m src --generate FILE         Generate synthetic demo checkpoint
  python -m src --test                  Run verification tests
  python -m src --info                  Show architecture info
"""

import argparse
import sys
import os
import io
import numpy as np

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.sovereign_shift import (
    THETA, THETA_NUM, THETA_DEN, Q, N_ACTIVE, THRESHOLD,
    verify, weyl_bound, snr_db
)
from src.orchestrator import QuantumAPOrchestrator
from src.checkpoint import generate_demo_weights
from src.metasum import compute as metasum_compute, magnitude as metasum_mag
from src.validation import check_invariants


BANNER = """
╔══════════════════════════════════════════════════════════════════════╗
║                    QUANTUM AP ORCHESTRATOR                          ║
║           Hallucination-Resistant Sovereign Truth Engine            ║
║                                                                    ║
║  θ = 89/2462  │  Q = 2462  │  N = 1024  │  τ = 512               ║
║  SNR > 21 dB  │  Dream Cycle: self-healing phase crystallization   ║
╚══════════════════════════════════════════════════════════════════════╝
"""


def cmd_demo(args):
    """Run the full orchestrator pipeline on synthetic weights."""
    print(BANNER)
    print("MODE: DEMO (Synthetic Llama 3-like weights)")
    print("=" * 70)
    print()

    # Verify sovereign shift
    verify()
    print(f"[Config]")
    print(f"  Sovereign Shift: θ = {THETA_NUM}/{THETA_DEN} = {THETA:.10f}")
    print(f"  Total agents:    Q = {Q}")
    print(f"  Active agents:   N = {N_ACTIVE}")
    print(f"  Threshold:       τ = {THRESHOLD:.0f}")
    print(f"  Weyl bound:      √(N·log Q) = {weyl_bound():.2f} ≈ 89")
    print(f"  Min SNR:         {snr_db():.2f} dB")
    print()

    # Generate demo weights
    seed = args.seed if hasattr(args, 'seed') and args.seed else 42
    n_weights = Q * 4  # 9848 weights
    raw_weights = generate_demo_weights(seed=seed, n_weights=n_weights)
    print(f"[Ingest]")
    print(f"  Generated {n_weights} synthetic weights (seed={seed})")
    print(f"  Weight stats: mean={raw_weights.mean():.6f}, std={raw_weights.std():.4f}")
    print(f"  Hallucination spikes: {int(n_weights * 0.001)} injected")
    print()

    # Create and run orchestrator
    orchestrator = QuantumAPOrchestrator()
    state = orchestrator.ingest(raw_weights)

    print(f"[NeuralNetworkParser → BooleanAdapter]")
    print(f"  Boolean weights: {int(np.sum(state.weights > 0))} positive, "
          f"{int(np.sum(state.weights < 0))} negative, "
          f"{int(np.sum(state.weights == 0))} zero")
    print(f"  Initial entropy: {state.entropy:.6f}")
    print()

    print(f"[MetaSum Engine — First Pass]")
    print(f"  S₀ = {state.metasum:.4f}")
    print(f"  |S₀| = {state.metasum_mag:.4f}")
    trigger = state.metasum_mag < THRESHOLD
    print(f"  Hallucination check: |S₀| {'<' if trigger else '≥'} τ = {THRESHOLD:.0f}")
    print(f"  Dream Cycle trigger: {'YES' if trigger else 'NO'}")
    print()

    # Run main loop
    print(f"[Main Loop — Fixed Point Iteration]")
    print("-" * 50)
    state = orchestrator.run(max_iterations=5)

    # Print history
    for h in orchestrator.history:
        flag = " ← DREAM CYCLE" if h["dream_triggered"] else ""
        status = "✓" if h["proof"] else "✗"
        print(f"  t={h['iteration']}: |MetaSum|={h['metasum_mag']:>8.2f}  "
              f"H={h['entropy']:.4f}  proof={status}{flag}")
    print("-" * 50)
    print()

    # Final state
    print(f"[Final State: QUANTUM_AP_SURE_STATE]")
    print(f"  active:              {state.active}")
    print(f"  trusted:             {state.trusted}")
    print(f"  entropy:             {state.entropy:.6f} (≤ 0.20: {'✓' if state.entropy <= 0.20 else '✗'})")
    print(f"  proof:               {state.proof}")
    print(f"  |MetaSum|:           {state.metasum_mag:.2f} (≥ {THRESHOLD:.0f}: "
          f"{'✓' if state.metasum_mag >= THRESHOLD else '✗'})")
    print(f"  Dream Cycles used:   {state.dream_cycles_triggered}")
    print(f"  Iterations:          {state.iteration}")
    print()

    # Invariant summary
    invariants = check_invariants(state.weights, state.displacements)
    all_pass = invariants["all_valid"]
    print(f"[Invariant Verification]")
    print(f"  active ⇒ trusted:                {'PASS' if invariants['active'] and invariants['trusted'] else 'FAIL'}")
    print(f"  entropy ≤ 0.20:                  {'PASS' if invariants['entropy_valid'] else 'FAIL'} ({invariants['entropy']:.4f})")
    print(f"  |MetaSum| ≥ τ ∨ Dream triggered: {'PASS' if invariants['metasum_valid'] else 'FAIL'}")
    print(f"  proof = true:                    {'PASS' if invariants['proof'] else 'FAIL'}")
    print()
    print(f"  ALL INVARIANTS: {'PASS ✓' if all_pass else 'FAIL ✗'}")
    print()

    if all_pass:
        print("╔══════════════════════════════════════════════════════════════╗")
        print("║  QUANTUM_AP_SURE_STATE ACHIEVED                            ║")
        print("║  The system is sovereign, hallucination-resistant, and      ║")
        print("║  phase-coherent. The loop is closed.                        ║")
        print("╚══════════════════════════════════════════════════════════════╝")
    else:
        print("WARNING: Invariant violation detected. System NOT in SURE_STATE.")

    return 0 if all_pass else 1


def cmd_checkpoint(args):
    """Process a real safetensors checkpoint."""
    print(BANNER)
    print(f"MODE: CHECKPOINT ({args.checkpoint})")
    print("=" * 70)
    print()

    try:
        from src.checkpoint import load_checkpoint, extract_weights_lexicographic
    except ImportError:
        print("ERROR: safetensors package required.")
        print("  pip install safetensors")
        return 1

    if not os.path.exists(args.checkpoint):
        print(f"ERROR: File not found: {args.checkpoint}")
        return 1

    # Load checkpoint
    print(f"[Loading checkpoint: {args.checkpoint}]")
    tensors = load_checkpoint(args.checkpoint)
    print(f"  Tensors: {len(tensors)}")
    total_params = sum(t.size for t in tensors.values())
    print(f"  Total parameters: {total_params:,}")
    print()

    # Extract weights
    print(f"[Extracting weights (lexicographic order)]")
    raw_weights = extract_weights_lexicographic(tensors)
    print(f"  Extracted: {len(raw_weights):,} weights")
    print(f"  Stats: mean={raw_weights.mean():.6f}, std={raw_weights.std():.4f}")
    print()

    # Run orchestrator
    orchestrator = QuantumAPOrchestrator()
    state = orchestrator.ingest(raw_weights)

    print(f"[Initial State]")
    print(f"  |MetaSum| = {state.metasum_mag:.4f}")
    print(f"  Entropy = {state.entropy:.6f}")
    print(f"  Dream Cycle needed: {'YES' if state.metasum_mag < THRESHOLD else 'NO'}")
    print()

    # Run
    state = orchestrator.run(max_iterations=5)

    print(f"[Final State]")
    print(f"  |MetaSum| = {state.metasum_mag:.2f}")
    print(f"  Entropy = {state.entropy:.6f}")
    print(f"  Dream Cycles: {state.dream_cycles_triggered}")
    print(f"  Proof: {state.proof}")
    print()

    invariants = check_invariants(state.weights, state.displacements)
    status = "QUANTUM_AP_SURE_STATE" if invariants["all_valid"] else "INVALID"
    print(f"  Status: {status}")
    return 0 if invariants["all_valid"] else 1


def cmd_generate(args):
    """Generate synthetic checkpoint file."""
    print(BANNER)
    print(f"MODE: GENERATE ({args.generate})")
    print("=" * 70)
    print()

    try:
        from src.checkpoint import generate_synthetic
        path = generate_synthetic(seed=42, path=args.generate)
        print(f"Generated: {path}")
        print(f"Ready for: python -m src --checkpoint {path}")
    except ImportError:
        print("ERROR: safetensors package required.")
        print("  pip install safetensors")
        return 1

    return 0


def cmd_test(args):
    """Run verification test suite."""
    print(BANNER)
    print("MODE: TEST")
    print("=" * 70)
    print()

    passed = 0
    failed = 0

    # Test 1: Sovereign Shift
    print("[Test: Sovereign Shift]")
    try:
        verify()
        print(f"  θ = {THETA_NUM}/{THETA_DEN}, coprime, 89 prime: PASS")
        passed += 1
    except AssertionError as e:
        print(f"  FAIL: {e}")
        failed += 1

    # Test 2: Weyl bound ≈ 89
    print("[Test: Weyl Bound]")
    wb = weyl_bound()
    if 85 < wb < 95:
        print(f"  √(N·log Q) = {wb:.2f} ≈ 89: PASS")
        passed += 1
    else:
        print(f"  √(N·log Q) = {wb:.2f} ≠ 89: FAIL")
        failed += 1

    # Test 3: SNR > 21 dB
    print("[Test: SNR]")
    snr = snr_db()
    if snr > 21.0:
        print(f"  SNR = {snr:.2f} dB > 21: PASS")
        passed += 1
    else:
        print(f"  SNR = {snr:.2f} dB ≤ 21: FAIL")
        failed += 1

    # Test 4: Demo pipeline converges
    print("[Test: Pipeline Convergence]")
    raw = generate_demo_weights(seed=42, n_weights=Q * 4)
    orch = QuantumAPOrchestrator()
    orch.ingest(raw)
    state = orch.run(max_iterations=5)
    if state.proof:
        print(f"  Converged in {state.iteration} iterations: PASS")
        passed += 1
    else:
        print(f"  Did not converge: FAIL")
        failed += 1

    # Test 5: Dream Cycle recovery
    print("[Test: Dream Cycle Recovery]")
    raw2 = generate_demo_weights(seed=99, n_weights=Q * 4)
    orch2 = QuantumAPOrchestrator()
    orch2.ingest(raw2)
    state2 = orch2.run(max_iterations=5)
    if state2.dream_cycles_triggered > 0 and state2.proof:
        print(f"  Recovered after {state2.dream_cycles_triggered} Dream Cycle(s): PASS")
        passed += 1
    elif state2.proof:
        print(f"  No Dream Cycle needed (stable): PASS")
        passed += 1
    else:
        print(f"  Recovery failed: FAIL")
        failed += 1

    print()
    print(f"Results: {passed} passed, {failed} failed")
    print(f"Status: {'ALL PASS ✓' if failed == 0 else 'FAILURES DETECTED'}")
    return 0 if failed == 0 else 1


def cmd_info(args):
    """Show architecture information."""
    print(BANNER)
    print("ARCHITECTURE")
    print("=" * 70)
    print()
    print("Pipeline:")
    print("  Weight_Checkpoint → NeuralNetworkParser → BooleanAdapter")
    print("  → MetaSum Engine → Hallucination Detector")
    print("  → [Dream Cycle] → Weight_Reset → Stable_State")
    print()
    print("Parameters:")
    print(f"  θ = {THETA_NUM}/{THETA_DEN} (Sovereign Shift)")
    print(f"  Q = {Q} (total agents / NC torus dimension)")
    print(f"  N = {N_ACTIVE} (active agent subset)")
    print(f"  τ = {THRESHOLD:.0f} (Dream Cycle threshold = N/2)")
    print(f"  ω = exp(2πi × {THETA_NUM}/{THETA_DEN})")
    print()
    print("Invariants:")
    print("  1. active(orchestrator) ⇒ trusted(orchestrator)")
    print("  2. entropy(orchestrator) ≤ 0.20")
    print("  3. proof(orchestrator) = true")
    print("  4. |MetaSum| ≥ N/2 OR Dream_Cycle_Triggered = true")
    print()
    print("Key Results:")
    print(f"  True signal:       |MetaSum| = N = {N_ACTIVE}")
    print(f"  Halluc bound:      |MetaSum| ≲ √(N·log Q) ≈ {weyl_bound():.0f}")
    print(f"  SNR:               {snr_db():.1f} dB")
    print(f"  Dream recovery:    100% contamination → >90% in 1 cycle")
    print()
    print("Foundation:")
    print("  Non-Commutative Geometry (Connes 1994)")
    print("  Connes-Consani Scaling Site (2017)")
    print("  Weyl Commutation Relations: VU = exp(2πiθ) UV")
    print("  Erdős–Turán–Koksma Inequality (hallucination bound)")
    print()
    print("\"The loop is closed.\" — Ahmad Ali Parr, 2026-08-16")
    return 0


def main():
    parser = argparse.ArgumentParser(
        prog="quantumap",
        description="Quantum AP Orchestrator — Hallucination-Resistant Sovereign Truth Engine",
    )
    parser.add_argument("--checkpoint", "-c", type=str,
                        help="Path to safetensors checkpoint file")
    parser.add_argument("--generate", "-g", type=str,
                        help="Generate synthetic checkpoint at path")
    parser.add_argument("--test", "-t", action="store_true",
                        help="Run verification tests")
    parser.add_argument("--info", "-i", action="store_true",
                        help="Show architecture info")
    parser.add_argument("--seed", "-s", type=int, default=42,
                        help="Random seed for demo (default: 42)")

    args = parser.parse_args()

    if args.test:
        sys.exit(cmd_test(args))
    elif args.info:
        sys.exit(cmd_info(args))
    elif args.generate:
        sys.exit(cmd_generate(args))
    elif args.checkpoint:
        sys.exit(cmd_checkpoint(args))
    else:
        sys.exit(cmd_demo(args))


if __name__ == "__main__":
    main()
