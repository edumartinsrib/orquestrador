#!/usr/bin/env bash
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for the browser SSO test." >&2
  exit 2
fi

python3 - <<'PY'
import importlib.util
import sys

if importlib.util.find_spec("playwright") is None:
    print("Python package playwright is required for the browser SSO test.", file=sys.stderr)
    sys.exit(2)
PY

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 "$repo_root/local/scripts/local-sso-browser-test.py"
