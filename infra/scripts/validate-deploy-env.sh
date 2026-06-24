#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
env_file="$repo_root/.env"

usage() {
  cat <<'EOF'
usage: ./infra/scripts/validate-deploy-env.sh [--env-file .env]

Validates that deployment environment values are present and are not example
placeholders. This script does not call AWS, Kubernetes, Docker, or GitHub.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      env_file="$2"
      shift 2
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

if [[ ! -f "$env_file" ]]; then
  echo "env file not found: $env_file" >&2
  exit 2
fi

# shellcheck disable=SC1091
source "$repo_root/infra/scripts/env-guard.sh"

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

required=(
  AWS_REGION
  AWS_ACCOUNT_ID
  AWS_ROLE_TO_ASSUME
  EKS_CLUSTER_NAME
  GITHUB_REPOSITORY
  GITHUB_REF_PATTERN
  TEMPORAL_HELM_CHART_VERSION
  TEMPORAL_SERVER_IMAGE_TAG
  TEMPORAL_ADMINTOOLS_IMAGE_TAG
  TEMPORAL_UI_IMAGE_TAG
  TEMPORAL_NAMESPACE
  TEMPORAL_DB_HOST
  TEMPORAL_DB_PORT
  TEMPORAL_DB_NAME
  TEMPORAL_VISIBILITY_DB_NAME
  TEMPORAL_DB_USER
  TEMPORAL_DB_PASSWORD
  TEMPORAL_UI_HOST
  TEMPORAL_UI_PUBLIC_URL
  TEMPORAL_AUTH_PROVIDER_URL
  TEMPORAL_AUTH_ISSUER_URL
  TEMPORAL_AUTH_CLIENT_ID
  TEMPORAL_AUTH_CLIENT_SECRET
  DEPLOY_KEYCLOAK
  ALB_CERTIFICATE_ARN
  ALB_SCHEME
)

if [[ "${DEPLOY_KEYCLOAK:-true}" == "true" ]]; then
  required+=(
    ECR_KEYCLOAK_REPOSITORY
    KEYCLOAK_IMAGE_TAG
    SSO_NAMESPACE
    TEMPORAL_INITIAL_ADMIN_USERNAME
    TEMPORAL_INITIAL_ADMIN_EMAIL
    TEMPORAL_INITIAL_ADMIN_PASSWORD
    KEYCLOAK_PUBLIC_HOSTNAME
    KEYCLOAK_PUBLIC_URL
    KEYCLOAK_DB_HOST
    KEYCLOAK_DB_PORT
    KEYCLOAK_DB_NAME
    KEYCLOAK_DB_USER
    KEYCLOAK_DB_PASSWORD
    KEYCLOAK_ADMIN_USERNAME
    KEYCLOAK_ADMIN_PASSWORD
  )
fi

env_guard_check_required "${required[@]}"
env_guard_check_real_values "${required[@]}"

echo "Deployment environment validation completed."
