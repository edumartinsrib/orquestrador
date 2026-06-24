#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
compose_file="$repo_root/local/docker-compose.yml"
env_file="$repo_root/local/.env.local"
worker_dir="$repo_root/worker"
worker_python="$worker_dir/.venv/bin/python"

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

curl_retry() {
  local url="$1"
  local label="$2"
  local retries="${3:-30}"
  local sleep_seconds="${4:-5}"
  local attempt

  for attempt in $(seq 1 "$retries"); do
    if curl --fail --silent --show-error --location --max-time 10 "$url" >/tmp/temporal-local-test-response.txt; then
      echo "OK: $label"
      return 0
    fi

    echo "Waiting for $label ($attempt/$retries)"
    sleep "$sleep_seconds"
  done

  echo "Failed: $label ($url)" >&2
  return 1
}

docker compose --env-file "$env_file" -f "$compose_file" ps

curl_retry "${KEYCLOAK_PUBLIC_URL%/}/realms/temporal/.well-known/openid-configuration" "Keycloak OIDC discovery"
curl_retry "http://localhost:8080/healthz" "Temporal UI health"

docker compose --env-file "$env_file" -f "$compose_file" exec -T keycloak /opt/keycloak/bin/reconcile-temporal-realm.sh
echo "OK: Keycloak realm reconciliation"

admin_token="$(
  curl --fail --silent --show-error \
    --request POST "${KEYCLOAK_PUBLIC_URL%/}/realms/master/protocol/openid-connect/token" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "client_id=admin-cli" \
    --data-urlencode "username=$KEYCLOAK_ADMIN_USERNAME" \
    --data-urlencode "password=$KEYCLOAK_ADMIN_PASSWORD" \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["access_token"])'
)"

initial_admin_user_json="$(
  curl --fail --silent --show-error \
  --header "Authorization: Bearer $admin_token" \
    "${KEYCLOAK_PUBLIC_URL%/}/admin/realms/temporal/users?username=$TEMPORAL_INITIAL_ADMIN_USERNAME&exact=true"
)"
initial_admin_user_id="$(
  python3 -c 'import json, os, sys; users = json.load(sys.stdin); assert len(users) == 1, users; user = users[0]; assert user["username"] == os.environ["TEMPORAL_INITIAL_ADMIN_USERNAME"], user; assert user["email"] == os.environ["TEMPORAL_INITIAL_ADMIN_EMAIL"], user; print(user["id"])' \
    <<<"$initial_admin_user_json"
)"
echo "OK: Keycloak initial Temporal user"

curl --fail --silent --show-error \
  --header "Authorization: Bearer $admin_token" \
  "${KEYCLOAK_PUBLIC_URL%/}/admin/realms/temporal/users/$initial_admin_user_id/role-mappings/realm" \
  | python3 -c 'import json, sys; roles = json.load(sys.stdin); assert any(role.get("name") == "temporal-admin" for role in roles), roles'
echo "OK: Keycloak initial Temporal user role"

if [[ ! -x "$worker_python" ]]; then
  python3 -m venv "$worker_dir/.venv"
fi

"$worker_python" -m pip install --upgrade pip >/dev/null
"$worker_python" -m pip install -r "$worker_dir/requirements.txt" >/dev/null

worker_log="$(mktemp)"
(
  cd "$worker_dir"
  TEMPORAL_ADDRESS="${TEMPORAL_ADDRESS:-localhost:7233}" \
  TEMPORAL_NAMESPACE="${TEMPORAL_NAMESPACE:-default}" \
  TEMPORAL_TASK_QUEUE="${TEMPORAL_TASK_QUEUE:-default-task-queue}" \
  TEMPORAL_WORKER_IDENTITY="${TEMPORAL_WORKER_IDENTITY:-local-python-worker}" \
  TEMPORAL_TLS_ENABLED="${TEMPORAL_TLS_ENABLED:-false}" \
    "$worker_python" -m temporal_worker.worker
) >"$worker_log" 2>&1 &
worker_pid="$!"

cleanup_worker() {
  if kill -0 "$worker_pid" >/dev/null 2>&1; then
    kill "$worker_pid" >/dev/null 2>&1 || true
    wait "$worker_pid" >/dev/null 2>&1 || true
  fi
  rm -f "$worker_log"
}
trap cleanup_worker EXIT

for attempt in $(seq 1 30); do
  if grep -q "Python Temporal worker started" "$worker_log"; then
    break
  fi
  if ! kill -0 "$worker_pid" >/dev/null 2>&1; then
    echo "Python worker exited before becoming ready:" >&2
    cat "$worker_log" >&2
    exit 1
  fi
  echo "Waiting for Python worker ($attempt/30)"
  sleep 1
done

if ! grep -q "Python Temporal worker started" "$worker_log"; then
  echo "Python worker did not become ready:" >&2
  cat "$worker_log" >&2
  exit 1
fi

client_output="$(
  cd "$worker_dir"
  TEMPORAL_ADDRESS="${TEMPORAL_ADDRESS:-localhost:7233}" \
  TEMPORAL_NAMESPACE="${TEMPORAL_NAMESPACE:-default}" \
  TEMPORAL_TASK_QUEUE="${TEMPORAL_TASK_QUEUE:-default-task-queue}" \
  TEMPORAL_WORKER_IDENTITY="local-python-client" \
  TEMPORAL_TLS_ENABLED="${TEMPORAL_TLS_ENABLED:-false}" \
    "$worker_python" -m temporal_worker.client Local
)"
echo "$client_output"

if ! grep -q "Python worker processed" <<<"$client_output"; then
  echo "Workflow was not processed by the Python worker:" >&2
  echo "$client_output" >&2
  exit 1
fi

echo "Local Temporal workflow test completed."
