#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
env_file="$repo_root/.env"
dry_run=false

# shellcheck disable=SC1091
source "$repo_root/infra/scripts/env-guard.sh"

usage() {
  cat <<'EOF'
usage: ./infra/scripts/configure-github-actions.sh [--env-file .env] [--dry-run]

Reads deployment values from a dotenv file and configures GitHub Actions
repository variables and secrets using the GitHub CLI.

Required dotenv key:
  GITHUB_REPOSITORY=owner/repo

Secrets are sent to gh through stdin.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      env_file="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=true
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

if [[ ! -f "$env_file" ]]; then
  echo "env file not found: $env_file" >&2
  exit 2
fi

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

repo="${GITHUB_REPOSITORY:-}"
if [[ -z "$repo" && "$(command -v gh || true)" ]]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
fi

if [[ -z "$repo" || "$repo" == "owner/repo" ]]; then
  echo "Set GITHUB_REPOSITORY=owner/repo in $env_file before configuring GitHub Actions." >&2
  exit 2
fi

if [[ "$dry_run" != "true" ]] && ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required." >&2
  exit 2
fi

require_real_value() {
  local name="$1"
  local value="${!name:-}"

  if [[ "$value" =~ $ENV_GUARD_PLACEHOLDER_REGEX ]]; then
    echo "Refusing to configure placeholder value for $name. Update $env_file first." >&2
    exit 2
  fi
}

set_variable() {
  local name="$1"
  local value="${!name:-}"

  require_real_value "$name"
  if [[ "$dry_run" == "true" ]]; then
    echo "Would set variable $name=$value"
  else
    printf '%s' "$value" | gh variable set "$name" --repo "$repo"
  fi
}

set_secret() {
  local name="$1"
  local value="${!name:-}"

  require_real_value "$name"
  if [[ "$dry_run" == "true" ]]; then
    echo "Would set secret $name=(redacted)"
  else
    printf '%s' "$value" | gh secret set "$name" --repo "$repo"
  fi
}

set_optional_secret() {
  local name="$1"
  local value="${!name:-}"

  if [[ -z "$value" ]]; then
    echo "Skipping optional empty secret $name"
    return
  fi

  if [[ "$value" =~ $ENV_GUARD_PLACEHOLDER_REGEX ]]; then
    echo "Refusing to configure placeholder value for optional secret $name." >&2
    exit 2
  fi

  if [[ "$dry_run" == "true" ]]; then
    echo "Would set optional secret $name=(redacted)"
  else
    printf '%s' "$value" | gh secret set "$name" --repo "$repo"
  fi
}

variables=(
  AWS_REGION
  AWS_ACCOUNT_ID
  AWS_ROLE_TO_ASSUME
  EKS_CLUSTER_NAME
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
  TEMPORAL_UI_HOST
  TEMPORAL_UI_PUBLIC_URL
  TEMPORAL_AUTH_PROVIDER_URL
  TEMPORAL_AUTH_ISSUER_URL
  TEMPORAL_AUTH_CLIENT_ID
  DEPLOY_KEYCLOAK
  ALB_CERTIFICATE_ARN
  ALB_SCHEME
)

secrets=(
  TEMPORAL_DB_PASSWORD
  TEMPORAL_AUTH_CLIENT_SECRET
)

if [[ "${DEPLOY_KEYCLOAK:-true}" == "true" ]]; then
  variables+=(
    ECR_KEYCLOAK_REPOSITORY
    KEYCLOAK_IMAGE_TAG
    SSO_NAMESPACE
    TEMPORAL_INITIAL_ADMIN_USERNAME
    TEMPORAL_INITIAL_ADMIN_EMAIL
    KEYCLOAK_PUBLIC_HOSTNAME
    KEYCLOAK_PUBLIC_URL
    KEYCLOAK_DB_HOST
    KEYCLOAK_DB_PORT
    KEYCLOAK_DB_NAME
    KEYCLOAK_DB_USER
    KEYCLOAK_ADMIN_USERNAME
  )
  secrets+=(
    TEMPORAL_INITIAL_ADMIN_PASSWORD
    KEYCLOAK_DB_PASSWORD
    KEYCLOAK_ADMIN_PASSWORD
  )
fi

echo "Configuring GitHub Actions for $repo"

for name in "${variables[@]}"; do
  set_variable "$name"
done

for name in "${secrets[@]}"; do
  set_secret "$name"
done

echo "GitHub Actions configuration completed."
