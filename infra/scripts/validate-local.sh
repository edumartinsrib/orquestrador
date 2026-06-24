#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
generated_dir="$repo_root/infra/generated/validation"
render="$repo_root/infra/scripts/render-env.sh"

mkdir -p "$generated_dir"

echo "==> Shell script syntax"
for script in "$repo_root"/infra/scripts/*.sh "$repo_root"/local/scripts/*.sh "$repo_root"/sso-keycloak/*.sh; do
  bash -n "$script"
done

echo "==> Worker Python validation"
(
  cd "$repo_root/worker"
  python3 -m venv .venv
  .venv/bin/python -m pip install --upgrade pip >/dev/null
  .venv/bin/python -m pip install -r requirements.txt >/dev/null
  .venv/bin/python -m pip check
  .venv/bin/python -m compileall -q temporal_worker
)

echo "==> Rendering Kubernetes and Helm templates"
set -a
# shellcheck disable=SC1091
source "$repo_root/.env.example"
set +a
export KEYCLOAK_IMAGE="${KEYCLOAK_IMAGE:-example.com/temporal-keycloak:validation}"

"$render" "$repo_root/infra/temporal/values.eks.tpl.yaml" "$generated_dir/temporal-values.yaml"
"$render" "$repo_root/infra/k8s/keycloak/keycloak.tpl.yaml" "$generated_dir/keycloak.yaml"
"$render" "$repo_root/infra/aws/github-oidc-trust-policy.tpl.json" "$generated_dir/github-oidc-trust-policy.json"

if command -v yq >/dev/null 2>&1; then
  yq e '.' "$generated_dir/temporal-values.yaml" >/dev/null
  yq e '.' "$generated_dir/keycloak.yaml" >/dev/null
  yq e '.' "$repo_root/local/docker-compose.yml" >/dev/null
  echo "YAML parse ok"
else
  echo "yq not found; skipped YAML parse"
fi

if command -v python3 >/dev/null 2>&1; then
  python3 -m json.tool "$repo_root/infra/aws/github-actions-policy.json" >/dev/null
  python3 -m json.tool "$generated_dir/github-oidc-trust-policy.json" >/dev/null
  python3 -m json.tool "$repo_root/sso-keycloak/realm-template.json" >/dev/null
  python3 -m py_compile "$repo_root/local/scripts/local-sso-browser-test.py"
  echo "JSON/Python parse ok"
else
  echo "python3 not found; skipped JSON parse"
fi

if command -v docker >/dev/null 2>&1; then
  docker compose --env-file "$repo_root/local/.env.local" -f "$repo_root/local/docker-compose.yml" config >/dev/null
  echo "==> Docker builds"
  docker build -t temporal-keycloak:validation "$repo_root/sso-keycloak"
  docker run --rm \
    -e TEMPORAL_UI_PUBLIC_URL=https://temporal.example.com \
    -e TEMPORAL_AUTH_CLIENT_ID=validation-temporal-ui \
    -e TEMPORAL_AUTH_CLIENT_SECRET=validation-secret \
    -e TEMPORAL_INITIAL_ADMIN_USERNAME=temporal.admin \
    -e TEMPORAL_INITIAL_ADMIN_EMAIL=temporal.admin@example.com \
    -e TEMPORAL_INITIAL_ADMIN_PASSWORD=validation-password \
    temporal-keycloak:validation show-config >/dev/null
  docker run --rm --entrypoint bash \
    -e TEMPORAL_UI_PUBLIC_URL=https://temporal.example.com \
    -e TEMPORAL_AUTH_CLIENT_ID=validation-temporal-ui \
    -e TEMPORAL_AUTH_CLIENT_SECRET=validation-secret \
    -e TEMPORAL_INITIAL_ADMIN_USERNAME=temporal.admin \
    -e TEMPORAL_INITIAL_ADMIN_EMAIL=temporal.admin@example.com \
    -e TEMPORAL_INITIAL_ADMIN_PASSWORD=validation-password \
    temporal-keycloak:validation \
    -lc '/opt/keycloak/bin/render-realm-and-start.sh show-config >/dev/null && grep -q "\"clientId\": \"validation-temporal-ui\"" /opt/keycloak/data/import/temporal-realm.json'
  docker run --rm --entrypoint bash temporal-keycloak:validation \
    -lc 'test -x /opt/keycloak/bin/reconcile-temporal-realm.sh && bash -n /opt/keycloak/bin/reconcile-temporal-realm.sh'
else
  echo "docker not found; skipped image builds"
fi

echo "Validation completed."
