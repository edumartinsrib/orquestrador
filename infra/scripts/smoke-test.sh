#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
env_file="${ENV_FILE:-$repo_root/.env}"

if [[ -f "$env_file" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
fi

required=(
  TEMPORAL_NAMESPACE
  TEMPORAL_UI_PUBLIC_URL
  TEMPORAL_AUTH_ISSUER_URL
)

if [[ "${DEPLOY_KEYCLOAK:-true}" == "true" ]]; then
  required+=(SSO_NAMESPACE KEYCLOAK_PUBLIC_URL)
fi

missing=()
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    missing+=("$name")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  printf 'missing required environment variables:\n' >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 2
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required for smoke tests." >&2
  exit 2
fi

http_checks="${SMOKE_PUBLIC_HTTP_CHECKS:-true}"
retries="${SMOKE_HTTP_RETRIES:-30}"
sleep_seconds="${SMOKE_HTTP_SLEEP_SECONDS:-10}"

kubectl_rollout() {
  local namespace="$1"
  local deployment="$2"

  echo "==> Waiting for deployment/$deployment in namespace $namespace"
  kubectl -n "$namespace" rollout status "deployment/$deployment" --timeout=5m
}

curl_retry() {
  local url="$1"
  local label="$2"
  local attempt

  for attempt in $(seq 1 "$retries"); do
    if curl --fail --silent --show-error --location --max-time 10 "$url" >/tmp/temporal-smoke-response.txt; then
      echo "HTTP check ok: $label"
      return 0
    fi

    echo "HTTP check waiting ($attempt/$retries): $label"
    sleep "$sleep_seconds"
  done

  echo "HTTP check failed: $label ($url)" >&2
  return 1
}

echo "==> Kubernetes rollouts"
kubectl_rollout "$TEMPORAL_NAMESPACE" temporal-frontend
kubectl_rollout "$TEMPORAL_NAMESPACE" temporal-history
kubectl_rollout "$TEMPORAL_NAMESPACE" temporal-matching
echo "==> temporal-worker is the internal Temporal system worker, not the local Python business worker"
kubectl_rollout "$TEMPORAL_NAMESPACE" temporal-worker
kubectl_rollout "$TEMPORAL_NAMESPACE" temporal-web

if [[ "${DEPLOY_KEYCLOAK:-true}" == "true" ]]; then
  kubectl_rollout "$SSO_NAMESPACE" keycloak
fi

echo "==> Kubernetes services"
kubectl -n "$TEMPORAL_NAMESPACE" get svc temporal-frontend temporal-web

if [[ "${DEPLOY_KEYCLOAK:-true}" == "true" ]]; then
  kubectl -n "$SSO_NAMESPACE" get svc keycloak
fi

if [[ "$http_checks" != "true" ]]; then
  echo "Skipping public HTTP checks because SMOKE_PUBLIC_HTTP_CHECKS=$http_checks"
  echo "Smoke tests completed."
  exit 0
fi

echo "==> Public HTTP checks"
curl_retry "${TEMPORAL_UI_PUBLIC_URL%/}/healthz" "Temporal UI health"
curl_retry "${TEMPORAL_AUTH_ISSUER_URL%/}/.well-known/openid-configuration" "OIDC discovery"

if [[ "${DEPLOY_KEYCLOAK:-true}" == "true" ]]; then
  curl_retry "${KEYCLOAK_PUBLIC_URL%/}/realms/temporal/.well-known/openid-configuration" "Keycloak temporal realm discovery"
fi

echo "Smoke tests completed."
