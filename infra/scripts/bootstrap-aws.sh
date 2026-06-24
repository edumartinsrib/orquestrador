#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
render="$repo_root/infra/scripts/render-env.sh"
generated_dir="$repo_root/infra/generated"
dry_run=false

# shellcheck disable=SC1091
source "$repo_root/infra/scripts/env-guard.sh"

usage() {
  cat <<'EOF'
usage: ./infra/scripts/bootstrap-aws.sh [--dry-run]

Creates the Keycloak ECR repository, a GitHub OIDC provider, and an IAM role/policy for
GitHub Actions deploys. With --dry-run, validates and renders local artifacts
without calling AWS.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

: "${AWS_ROLE_NAME:=github-actions-temporal-deploy}"
: "${AWS_POLICY_NAME:=github-actions-temporal-deploy-policy}"
: "${DEPLOY_KEYCLOAK:=true}"

required=(
  AWS_REGION
  EKS_CLUSTER_NAME
  GITHUB_REPOSITORY
  GITHUB_REF_PATTERN
)

if [[ "$DEPLOY_KEYCLOAK" == "true" ]]; then
  required+=(ECR_KEYCLOAK_REPOSITORY)
fi

if [[ "$dry_run" == "true" ]]; then
  required+=(AWS_ACCOUNT_ID)
fi

env_guard_check_required "${required[@]}"
env_guard_check_real_values "${required[@]}"

env_guard_check_real_values AWS_ROLE_NAME AWS_POLICY_NAME DEPLOY_KEYCLOAK

mkdir -p "$generated_dir"

if [[ "$dry_run" == "true" ]]; then
  "$render" "$repo_root/infra/aws/github-oidc-trust-policy.tpl.json" "$generated_dir/github-oidc-trust-policy.json"

  if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$generated_dir/github-oidc-trust-policy.json" >/dev/null
    python3 -m json.tool "$repo_root/infra/aws/github-actions-policy.json" >/dev/null
  fi

  cat <<EOF
Dry run completed. No AWS calls were made.

Would ensure:
$(if [[ "$DEPLOY_KEYCLOAK" == "true" ]]; then printf '%s\n' "- ECR repository: $ECR_KEYCLOAK_REPOSITORY"; else printf '%s\n' "- No ECR repository; DEPLOY_KEYCLOAK=false"; fi)
- GitHub OIDC provider: token.actions.githubusercontent.com
- IAM role: $AWS_ROLE_NAME
- IAM inline policy: $AWS_POLICY_NAME

Rendered trust policy:
- $generated_dir/github-oidc-trust-policy.json
EOF
  exit 0
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI is required." >&2
  exit 2
fi

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export AWS_ACCOUNT_ID

ensure_ecr_repository() {
  local repository="$1"

  if aws ecr describe-repositories \
    --region "$AWS_REGION" \
    --repository-names "$repository" >/dev/null 2>&1; then
    echo "ECR repository exists: $repository"
    return
  fi

  aws ecr create-repository \
    --region "$AWS_REGION" \
    --repository-name "$repository" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 >/dev/null

  echo "Created ECR repository: $repository"
}

ensure_github_oidc_provider() {
  local provider_arn="arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"

  if aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "$provider_arn" >/dev/null 2>&1; then
    echo "GitHub OIDC provider exists: $provider_arn"
    return
  fi

  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 >/dev/null

  echo "Created GitHub OIDC provider: $provider_arn"
}

ensure_iam_role() {
  local trust_policy="$generated_dir/github-oidc-trust-policy.json"
  local policy_doc="$repo_root/infra/aws/github-actions-policy.json"
  local role_arn

  "$render" "$repo_root/infra/aws/github-oidc-trust-policy.tpl.json" "$trust_policy"

  if aws iam get-role --role-name "$AWS_ROLE_NAME" >/dev/null 2>&1; then
    aws iam update-assume-role-policy \
      --role-name "$AWS_ROLE_NAME" \
      --policy-document "file://$trust_policy" >/dev/null
    echo "Updated IAM role trust policy: $AWS_ROLE_NAME"
  else
    aws iam create-role \
      --role-name "$AWS_ROLE_NAME" \
      --assume-role-policy-document "file://$trust_policy" >/dev/null
    echo "Created IAM role: $AWS_ROLE_NAME"
  fi

  role_arn="$(aws iam get-role --role-name "$AWS_ROLE_NAME" --query 'Role.Arn' --output text)"

  aws iam put-role-policy \
    --role-name "$AWS_ROLE_NAME" \
    --policy-name "$AWS_POLICY_NAME" \
    --policy-document "file://$policy_doc" >/dev/null

  echo "Attached inline policy: $AWS_POLICY_NAME"
  echo
  echo "AWS_ROLE_TO_ASSUME=$role_arn"
  echo
  echo "Run these commands once to grant this role Kubernetes access to EKS:"
  echo "aws eks create-access-entry --region \"$AWS_REGION\" --cluster-name \"$EKS_CLUSTER_NAME\" --principal-arn \"$role_arn\" --type STANDARD"
  echo "aws eks associate-access-policy --region \"$AWS_REGION\" --cluster-name \"$EKS_CLUSTER_NAME\" --principal-arn \"$role_arn\" --access-scope type=cluster --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
}

if [[ "$DEPLOY_KEYCLOAK" == "true" ]]; then
  ensure_ecr_repository "$ECR_KEYCLOAK_REPOSITORY"
fi
ensure_github_oidc_provider
ensure_iam_role
