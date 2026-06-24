#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
generated_dir="$repo_root/infra/generated/validation"
render="$repo_root/infra/scripts/render-env.sh"

: "${HELM_IMAGE:=alpine/helm:3.18.6}"
: "${ACTIONLINT_IMAGE:=rhysd/actionlint:1.7.12}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for extended validation." >&2
  exit 2
fi

mkdir -p "$generated_dir"

set -a
# shellcheck disable=SC1091
source "$repo_root/.env.example"
set +a

export KEYCLOAK_IMAGE="${KEYCLOAK_IMAGE:-example.com/temporal-keycloak:validation}"

"$render" "$repo_root/infra/temporal/values.eks.tpl.yaml" "$generated_dir/temporal-values.yaml"
"$render" "$repo_root/infra/k8s/keycloak/keycloak.tpl.yaml" "$generated_dir/keycloak.yaml"

echo "==> Rendering Temporal Helm chart"
docker run --rm --entrypoint sh \
  -v "$repo_root:/work:ro" \
  -w /work \
  -e TEMPORAL_HELM_CHART_VERSION="$TEMPORAL_HELM_CHART_VERSION" \
  "$HELM_IMAGE" \
  -lc 'helm repo add temporal https://go.temporal.io/helm-charts >/dev/null && helm repo update temporal >/dev/null && helm template temporal temporal/temporal --namespace temporal --version "$TEMPORAL_HELM_CHART_VERSION" -f infra/generated/validation/temporal-values.yaml' \
  > "$generated_dir/temporal-helm-rendered.yaml"

if command -v yq >/dev/null 2>&1; then
  echo "==> Checking rendered Kubernetes objects"
  rendered_objects="$(yq e -N 'select(.kind != null) | .kind + "/" + .metadata.name' "$generated_dir/temporal-helm-rendered.yaml")"

  for object in \
    Deployment/temporal-frontend \
    Deployment/temporal-history \
    Deployment/temporal-matching \
    Deployment/temporal-worker \
    Deployment/temporal-web \
    Ingress/temporal-web \
    Service/temporal-frontend \
    Service/temporal-web; do
    if ! grep -Fxq "$object" <<<"$rendered_objects"; then
      echo "missing rendered object: $object" >&2
      exit 1
    fi
  done

  auth_type="$(
    yq e -N 'select(.kind == "Deployment" and .metadata.name == "temporal-web") | .spec.template.spec.containers[] | select(.name == "temporal-web") | .env[]? | select(.name == "TEMPORAL_AUTH_TYPE") | .value' \
      "$generated_dir/temporal-helm-rendered.yaml"
  )"
  if [[ "$auth_type" != "oidc" ]]; then
    echo "Temporal UI auth type is not oidc: $auth_type" >&2
    exit 1
  fi

  assert_temporal_web_env() {
    local name="$1"
    local expected="$2"
    local actual

    actual="$(
      NAME="$name" yq e -N 'select(.kind == "Deployment" and .metadata.name == "temporal-web") | .spec.template.spec.containers[] | select(.name == "temporal-web") | .env[]? | select(.name == strenv(NAME)) | .value' \
        "$generated_dir/temporal-helm-rendered.yaml" \
        | tail -n 1
    )"
    if [[ "$actual" != "$expected" ]]; then
      echo "Temporal UI env $name expected '$expected' but rendered '$actual'" >&2
      exit 1
    fi
  }

  assert_temporal_web_env TEMPORAL_AUTH_PROVIDER_URL "$TEMPORAL_AUTH_PROVIDER_URL"
  assert_temporal_web_env TEMPORAL_AUTH_ISSUER_URL "$TEMPORAL_AUTH_ISSUER_URL"
  assert_temporal_web_env TEMPORAL_AUTH_CLIENT_ID "$TEMPORAL_AUTH_CLIENT_ID"
  assert_temporal_web_env TEMPORAL_AUTH_CALLBACK_URL "${TEMPORAL_UI_PUBLIC_URL%/}/auth/sso/callback"

  if ! yq e -N 'select(.kind == "Deployment" and .metadata.name == "temporal-web") | .spec.template.spec.containers[] | select(.name == "temporal-web") | .envFrom[]?.secretRef.name' \
    "$generated_dir/temporal-helm-rendered.yaml" | grep -Fxq temporal-ui-auth-secret; then
    echo "Temporal UI deployment does not reference temporal-ui-auth-secret" >&2
    exit 1
  fi

  echo "==> Checking Temporal database secret wiring"
  for deployment in temporal-frontend temporal-history temporal-matching temporal-worker; do
    for env_name in TEMPORAL_DEFAULT_STORE_PASSWORD TEMPORAL_VISIBILITY_STORE_PASSWORD; do
      secret_ref="$(
        DEPLOYMENT="$deployment" ENV_NAME="$env_name" yq e -N 'select(.kind == "Deployment" and .metadata.name == strenv(DEPLOYMENT)) | .spec.template.spec.containers[]? | .env[]? | select(.name == strenv(ENV_NAME)) | .valueFrom.secretKeyRef.name + ":" + .valueFrom.secretKeyRef.key' \
          "$generated_dir/temporal-helm-rendered.yaml"
      )"
      if [[ "$secret_ref" != "temporal-db-secret:password" ]]; then
        echo "$deployment env $env_name must reference temporal-db-secret:password; rendered '$secret_ref'" >&2
        exit 1
      fi
    done
  done

  rendered_images="$(
    yq e -N 'select(.kind == "Deployment") | .spec.template.spec.containers[]?.image' \
      "$generated_dir/temporal-helm-rendered.yaml"
  )"
  for expected_image in \
    "temporalio/server:$TEMPORAL_SERVER_IMAGE_TAG" \
    "temporalio/ui:$TEMPORAL_UI_IMAGE_TAG"; do
    if ! grep -Fxq "$expected_image" <<<"$rendered_images"; then
      echo "Rendered Temporal chart does not include image $expected_image" >&2
      exit 1
    fi
  done

  assert_deployment_security_context() {
    local manifest="$1"
    local deployment="$2"
    local container="$3"
    local pod_run_as_non_root
    local pod_seccomp_type
    local container_allow_privilege_escalation
    local container_capability_drop

    pod_run_as_non_root="$(
      DEPLOYMENT="$deployment" yq e -N 'select(.kind == "Deployment" and .metadata.name == strenv(DEPLOYMENT)) | .spec.template.spec.securityContext.runAsNonRoot' \
        "$manifest"
    )"
    pod_seccomp_type="$(
      DEPLOYMENT="$deployment" yq e -N 'select(.kind == "Deployment" and .metadata.name == strenv(DEPLOYMENT)) | .spec.template.spec.securityContext.seccompProfile.type' \
        "$manifest"
    )"
    container_allow_privilege_escalation="$(
      DEPLOYMENT="$deployment" CONTAINER="$container" yq e -N 'select(.kind == "Deployment" and .metadata.name == strenv(DEPLOYMENT)) | .spec.template.spec.containers[] | select(.name == strenv(CONTAINER)) | .securityContext.allowPrivilegeEscalation' \
        "$manifest"
    )"
    container_capability_drop="$(
      DEPLOYMENT="$deployment" CONTAINER="$container" yq e -N 'select(.kind == "Deployment" and .metadata.name == strenv(DEPLOYMENT)) | .spec.template.spec.containers[] | select(.name == strenv(CONTAINER)) | .securityContext.capabilities.drop[]?' \
        "$manifest"
    )"

    if [[ "$pod_run_as_non_root" != "true" ]]; then
      echo "$deployment pod securityContext.runAsNonRoot must be true" >&2
      exit 1
    fi
    if [[ "$pod_seccomp_type" != "RuntimeDefault" ]]; then
      echo "$deployment pod securityContext.seccompProfile.type must be RuntimeDefault" >&2
      exit 1
    fi
    if [[ "$container_allow_privilege_escalation" != "false" ]]; then
      echo "$deployment/$container securityContext.allowPrivilegeEscalation must be false" >&2
      exit 1
    fi
    if ! grep -Fxq ALL <<<"$container_capability_drop"; then
      echo "$deployment/$container securityContext.capabilities.drop must include ALL" >&2
      exit 1
    fi
  }

  echo "==> Checking workload security contexts"
  assert_deployment_security_context "$generated_dir/keycloak.yaml" keycloak keycloak

  echo "==> Checking secret env wiring"
  for manifest in "$generated_dir/keycloak.yaml" "$generated_dir/temporal-helm-rendered.yaml"; do
    literal_secret_env="$(
      yq e -N 'select(.kind == "Deployment") | .metadata.name as $deployment | .spec.template.spec.containers[]? | .name as $container | .env[]? | select(.name | test("PASSWORD|SECRET|TOKEN")) | select(has("value")) | $deployment + "/" + $container + "/" + .name' \
        "$manifest"
    )"
    if [[ -n "$literal_secret_env" ]]; then
      echo "secret-like env vars must not use literal values in $manifest:" >&2
      echo "$literal_secret_env" >&2
      exit 1
    fi

    missing_secret_ref="$(
      yq e -N 'select(.kind == "Deployment") | .metadata.name as $deployment | .spec.template.spec.containers[]? | .name as $container | .env[]? | select(.name | test("PASSWORD|SECRET|TOKEN")) | select(.valueFrom.secretKeyRef.name == null) | $deployment + "/" + $container + "/" + .name' \
        "$manifest"
    )"
    if [[ -n "$missing_secret_ref" ]]; then
      echo "secret-like env vars must use valueFrom.secretKeyRef in $manifest:" >&2
      echo "$missing_secret_ref" >&2
      exit 1
    fi
  done
else
  echo "yq not found; skipped rendered object assertions"
fi

echo "==> Linting GitHub Actions workflows"
docker run --rm \
  -v "$repo_root:/repo:ro" \
  -w /repo \
  "$ACTIONLINT_IMAGE" \
  .github/workflows/deploy.yml .github/workflows/validate.yml

echo "Extended validation completed."
