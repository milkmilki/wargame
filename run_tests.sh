#!/usr/bin/env bash
# Native Atlas 2D and shared simulation regressions.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON:-python3}" "$PROJECT_DIR/run_tests.py" "$@"
