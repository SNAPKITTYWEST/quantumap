#!/usr/bin/env python3
"""
QuantumAP — Quantum AP Orchestrator
Direct entry point: python quantumap.py

Usage:
  python quantumap.py                   # Demo mode
  python quantumap.py --checkpoint FILE # Process safetensors
  python quantumap.py --test            # Run tests
  python quantumap.py --info            # Architecture info
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src.cli import main

if __name__ == "__main__":
    main()
