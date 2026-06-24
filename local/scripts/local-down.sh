#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
compose_file="$repo_root/local/docker-compose.yml"
env_file="$repo_root/local/.env.local"

args=(down --remove-orphans)
if [[ "${1:-}" == "--volumes" ]]; then
  args+=(--volumes)
fi

docker compose --env-file "$env_file" -f "$compose_file" "${args[@]}"
