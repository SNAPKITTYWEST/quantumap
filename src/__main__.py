"""
QuantumAP CLI entry point.

Usage:
  python -m src                         # Run demo (synthetic weights)
  python -m src --checkpoint FILE       # Process real safetensors file
  python -m src --generate FILE         # Generate synthetic checkpoint
  python -m src --test                  # Run test suite
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.cli import main

if __name__ == "__main__":
    main()
