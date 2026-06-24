#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
generated_dir="$repo_root/infra/generated"
render="$repo_root/infra/scripts/render-env.sh"
check_env_only=false

# shellcheck disable=SC1091
source "$repo_root/infra/scripts/env-guard.sh"

usage() {
  cat <<'EOF'
usage: ./infra/scripts/deploy.sh [--check-env-only]

Deploys Temporal OSS and, when DEPLOY_KEYCLOAK=true, Keycloak to Kubernetes.
With --check-env-only, validates required environment variables and renders
templates without calling Kubernetes, Helm, AWS, Docker, or GitHub.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-env-only)
      check_env_only=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${DEPLOY_KEYCLOAK:-true}" == "true" && -z "${KEYCLOAK_IMAGE:-}" && -n "${AWS_ACCOUNT_ID:-}" && -n "${ECR_KEYCLOAK_REPOSITORY:-}" ]]; then
  KEYCLOAK_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_KEYCLOAK_REPOSITORY:${IMAGE_TAG:-local}"
  export KEYCLOAK_IMAGE
fi

required=(
  AWS_REGION
  EKS_CLUSTER_NAME
  TEMPORAL_NAMESPACE
  TEMPORAL_DB_HOST
  TEMPORAL_DB_PORT
  TEMPORAL_DB_NAME
  TEMPORAL_VISIBILITY_DB_NAME
  TEMPORAL_DB_USER
  TEMPORAL_DB_PASSWORD
  TEMPORAL_HELM_CHART_VERSION
  TEMPORAL_SERVER_IMAGE_TAG
  TEMPORAL_ADMINTOOLS_IMAGE_TAG
  TEMPORAL_UI_IMAGE_TAG
  TEMPORAL_UI_HOST
  TEMPORAL_UI_PUBLIC_URL
  TEMPORAL_AUTH_PROVIDER_URL
  TEMPORAL_AUTH_ISSUER_URL
  TEMPORAL_AUTH_CLIENT_ID
  TEMPORAL_AUTH_CLIENT_SECRET
  ALB_CERTIFICATE_ARN
  ALB_SCHEME
)

if [[ "${DEPLOY_KEYCLOAK:-true}" == "true" ]]; then
  required+=(
    SSO_NAMESPACE
    KEYCLOAK_IMAGE
    KEYCLOAK_PUBLIC_HOSTNAME
    KEYCLOAK_PUBLIC_URL
    KEYCLOAK_DB_HOST
    KEYCLOAK_DB_PORT
    KEYCLOAK_DB_NAME
    KEYCLOAK_DB_USER
    KEYCLOAK_DB_PASSWORD
    KEYCLOAK_ADMIN_USERNAME
    KEYCLOAK_ADMIN_PASSWORD
    TEMPORAL_INITIAL_ADMIN_USERNAME
    TEMPORAL_INITIAL_ADMIN_EMAIL
    TEMPORAL_INITIAL_ADMIN_PASSWORD
  )
fi

env_guard_check_required "${required[@]}"
env_guard_check_real_values "${required[@]}"

mkdir -p "$generated_dir"

if [[ "$check_env_only" == "true" ]]; then
  "$render" "$repo_root/infra/temporal/values.eks.tpl.yaml" "$generated_dir/temporal-values.yaml"

  if [[ "${DEPLOY_KEYCLOAK:-true}" == "true" ]]; then
    "$render" "$repo_root/infra/k8s/keycloak/keycloak.tpl.yaml" "$generated_dir/keycloak.yaml"
  fi

  echo "Deployment environment and template render validation completed."
  exit 0
fi

kubectl create namespace "$TEMPORAL_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$TEMPORAL_NAMESPACE" create secret generic temporal-db-secret \
  --from-literal=password="$TEMPORAL_DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$TEMPORAL_NAMESPACE" create secret generic temporal-ui-auth-secret \
  --from-literal=TEMPORAL_AUTH_CLIENT_SECRET="$TEMPORAL_AUTH_CLIENT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

"$render" "$repo_root/infra/temporal/values.eks.tpl.yaml" "$generated_dir/temporal-values.yaml"

helm repo add temporal https://go.temporal.io/helm-charts >/dev/null
helm repo update temporal >/dev/null
helm upgrade --install temporal temporal/temporal \
  --namespace "$TEMPORAL_NAMESPACE" \
  --version "$TEMPORAL_HELM_CHART_VERSION" \
  --values "$generated_dir/temporal-values.yaml" \
  --timeout 15m \
  --wait

if [[ "${DEPLOY_KEYCLOAK:-true}" == "true" ]]; then
  kubectl create namespace "$SSO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  kubectl -n "$SSO_NAMESPACE" create secret generic keycloak-runtime-secret \
    --from-literal=KC_BOOTSTRAP_ADMIN_USERNAME="$KEYCLOAK_ADMIN_USERNAME" \
    --from-literal=KC_BOOTSTRAP_ADMIN_PASSWORD="$KEYCLOAK_ADMIN_PASSWORD" \
    --from-literal=KC_DB_PASSWORD="$KEYCLOAK_DB_PASSWORD" \
    --from-literal=TEMPORAL_AUTH_CLIENT_SECRET="$TEMPORAL_AUTH_CLIENT_SECRET" \
    --from-literal=TEMPORAL_INITIAL_ADMIN_PASSWORD="$TEMPORAL_INITIAL_ADMIN_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

  "$render" "$repo_root/infra/k8s/keycloak/keycloak.tpl.yaml" "$generated_dir/keycloak.yaml"
  kubectl apply -f "$generated_dir/keycloak.yaml"
  kubectl -n "$SSO_NAMESPACE" rollout status deployment/keycloak --timeout=5m
  kubectl -n "$SSO_NAMESPACE" exec deployment/keycloak -- /opt/keycloak/bin/reconcile-temporal-realm.sh
fi

kubectl -n "$TEMPORAL_NAMESPACE" rollout status deployment/temporal-frontend --timeout=5m
kubectl -n "$TEMPORAL_NAMESPACE" rollout status deployment/temporal-web --timeout=5m
