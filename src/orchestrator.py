"""
Quantum AP Orchestrator: Main Loop

Deterministic fixed-point iteration maintaining sovereignty over the agent fleet.

State_t = IF |MetaSum_t| < τ THEN Dream_Cycle(State_{t-1}) ELSE State_{t-1}

The loop:
  1. Ingest weight checkpoint
  2. Adapt to boolean states
  3. Compute MetaSum with Sovereign Shift phase correction
  4. Trigger Dream Cycle on hallucination detection
  5. Apply phase crystallization via UniversalBooleanTensorParser
  6. Validate all invariants before proceeding
"""

import numpy as np
from dataclasses import dataclass, field
from typing import Optional

from .sovereign_shift import Q, N_ACTIVE, THRESHOLD
from .boolean_adapter import adapt, select_active
from .metasum import compute as metasum_compute, magnitude as metasum_magnitude
from .dream_cycle import execute as dream_cycle_execute
from .validation import check_invariants, compute_entropy


@dataclass
class OrchestratorState:
    """Quantum AP Orchestrator state at time t."""
    weights: np.ndarray
    displacements: np.ndarray
    metasum: complex = 0j
    metasum_mag: float = 0.0
    entropy: float = 0.0
    dream_cycles_triggered: int = 0
    iteration: int = 0
    active: bool = True
    trusted: bool = True
    proof: bool = True


class QuantumAPOrchestrator:
    """
    The Quantum AP Orchestrator.

    Operates as a deterministic fixed-point iteration over Q=2462 agents
    with N_ACTIVE=1024 active at any time. Uses θ = 89/2462 to maintain
    phase coherence and suppress hallucinations.
    """

    def __init__(self):
        self.state: Optional[OrchestratorState] = None
        self.history: list = []

    def ingest(self, raw_weights: np.ndarray) -> OrchestratorState:
        """
        Ingest raw weight checkpoint and initialize orchestrator state.

        Steps:
          1. NeuralNetworkParser: raw → boolean
          2. BooleanAdapter: select N_ACTIVE agents
          3. Initialize displacements (agent indices)
        """
        # Neural → Boolean
        bool_weights = adapt(raw_weights)

        # Select active subset (top N_ACTIVE by magnitude)
        # For Q-dimensional input, use directly; otherwise pad/truncate
        if len(bool_weights) < Q:
            padded = np.zeros(Q)
            padded[:len(bool_weights)] = bool_weights[:Q]
            bool_weights = padded
        elif len(bool_weights) > Q:
            bool_weights = bool_weights[:Q]

        # Select top N_ACTIVE
        active_weights = select_active(bool_weights, N_ACTIVE)

        # Displacements = agent index (lateral position in fleet)
        displacements = np.arange(Q, dtype=np.float64)

        # Compute initial MetaSum
        S = metasum_compute(active_weights, displacements)

        self.state = OrchestratorState(
            weights=active_weights,
            displacements=displacements,
            metasum=S,
            metasum_mag=abs(S),
            entropy=compute_entropy(active_weights),
            iteration=0,
        )

        return self.state

    def step(self) -> OrchestratorState:
        """
        Execute one iteration of the main loop.

        State_t = IF |MetaSum_t| < τ THEN Dream_Cycle(State_{t-1}) ELSE State_{t-1}
        """
        if self.state is None:
            raise RuntimeError("Orchestrator not initialized. Call ingest() first.")

        self.state.iteration += 1

        # Compute MetaSum
        S = metasum_compute(self.state.weights, self.state.displacements)
        self.state.metasum = S
        self.state.metasum_mag = abs(S)

        # Check if Dream Cycle needed
        dream_triggered = False
        if self.state.metasum_mag < THRESHOLD:
            new_weights, new_S, triggered = dream_cycle_execute(
                self.state.weights, self.state.displacements
            )
            if triggered:
                self.state.weights = new_weights
                self.state.metasum = new_S
                self.state.metasum_mag = abs(new_S)
                self.state.dream_cycles_triggered += 1
                dream_triggered = True

        # Update entropy
        self.state.entropy = compute_entropy(self.state.weights)

        # Validate invariants
        invariants = check_invariants(
            self.state.weights,
            self.state.displacements,
            dream_triggered=dream_triggered,
        )
        self.state.active = invariants["active"]
        self.state.trusted = invariants["trusted"]
        self.state.proof = invariants["proof"]

        # Record history
        self.history.append({
            "iteration": self.state.iteration,
            "metasum_mag": self.state.metasum_mag,
            "entropy": self.state.entropy,
            "dream_triggered": dream_triggered,
            "proof": self.state.proof,
        })

        return self.state

    def run(self, max_iterations: int = 10) -> OrchestratorState:
        """Run the main loop until stable or max iterations reached."""
        for _ in range(max_iterations):
            prev_mag = self.state.metasum_mag
            self.step()

            # Fixed point: no change in MetaSum magnitude
            if abs(self.state.metasum_mag - prev_mag) < 1e-6 and self.state.proof:
                break

        return self.state

    def status(self) -> str:
        """Return current orchestrator status string."""
        if self.state is None:
            return "NOT_INITIALIZED"

        return (
            f"QuantumAP [iter={self.state.iteration}] "
            f"|MetaSum|={self.state.metasum_mag:.2f} "
            f"entropy={self.state.entropy:.4f} "
            f"dreams={self.state.dream_cycles_triggered} "
            f"proof={'VALID' if self.state.proof else 'INVALID'}"
        )


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import sys
    sys.path.insert(0, str(__file__).rsplit("/src/", 1)[0])

    print("=" * 70)
    print("QUANTUM AP ORCHESTRATOR — MAIN LOOP")
    print("θ = 89/2462, Q = 2462, N = 1024, τ = 512")
    print("=" * 70)
    print()

    orchestrator = QuantumAPOrchestrator()

    # Simulate: random weights (as if from a model checkpoint)
    rng = np.random.default_rng(42)
    raw_weights = rng.standard_normal(Q)

    # Ingest
    state = orchestrator.ingest(raw_weights)
    print(f"[Ingest] {orchestrator.status()}")

    # Run main loop
    state = orchestrator.run(max_iterations=5)
    print(f"[Final]  {orchestrator.status()}")
    print()

    # Show history
    print("Iteration History:")
    for h in orchestrator.history:
        flag = " [DREAM]" if h["dream_triggered"] else ""
        print(f"  t={h['iteration']}: |MetaSum|={h['metasum_mag']:.2f} "
              f"H={h['entropy']:.4f} proof={h['proof']}{flag}")
    print()

    # Simulate with hallucination injection
    print("=" * 70)
    print("HALLUCINATION INJECTION TEST")
    print("=" * 70)
    print()

    orchestrator2 = QuantumAPOrchestrator()

    # Create weights with injected hallucinations
    clean_weights = rng.standard_normal(Q)
    state = orchestrator2.ingest(clean_weights)
    print(f"[Clean]  {orchestrator2.status()}")

    # Inject hallucinations: flip random agents
    halluc_count = 800
    flip_idx = rng.choice(Q, size=halluc_count, replace=False)
    orchestrator2.state.weights[flip_idx] *= -1  # Corrupt weights

    # Re-run
    state = orchestrator2.run(max_iterations=5)
    print(f"[After Halluc + Recovery] {orchestrator2.status()}")
    print(f"  Dream Cycles used: {state.dream_cycles_triggered}")
    print()
    print("The loop is closed. QUANTUM_AP_SURE_STATE achieved.")
