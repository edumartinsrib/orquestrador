#!/usr/bin/env bash
set -euo pipefail

temporal_address="${TEMPORAL_ADDRESS:-127.0.0.1:7233}"
ui_port="${TEMPORAL_UI_PORT:-8080}"

temporal operator cluster health --address "$temporal_address" >/dev/null

if [[ "${TEMPORAL_UI_ENABLED:-true}" != "false" ]]; then
  curl -fsS "http://127.0.0.1:${ui_port}/healthz" >/dev/null
fi
