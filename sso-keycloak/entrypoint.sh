#!/usr/bin/env bash
set -euo pipefail

template="/opt/keycloak/templates/realm-template.json"
rendered="/opt/keycloak/data/import/temporal-realm.json"

required=(
  TEMPORAL_UI_PUBLIC_URL
  TEMPORAL_AUTH_CLIENT_ID
  TEMPORAL_AUTH_CLIENT_SECRET
  TEMPORAL_INITIAL_ADMIN_USERNAME
  TEMPORAL_INITIAL_ADMIN_EMAIL
  TEMPORAL_INITIAL_ADMIN_PASSWORD
)

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

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

cp "$template" "$rendered"
sed -i "s/\${TEMPORAL_UI_PUBLIC_URL}/$(escape_sed "$TEMPORAL_UI_PUBLIC_URL")/g" "$rendered"
sed -i "s/\${TEMPORAL_AUTH_CLIENT_ID}/$(escape_sed "$TEMPORAL_AUTH_CLIENT_ID")/g" "$rendered"
sed -i "s/\${TEMPORAL_AUTH_CLIENT_SECRET}/$(escape_sed "$TEMPORAL_AUTH_CLIENT_SECRET")/g" "$rendered"
sed -i "s/\${TEMPORAL_INITIAL_ADMIN_USERNAME}/$(escape_sed "$TEMPORAL_INITIAL_ADMIN_USERNAME")/g" "$rendered"
sed -i "s/\${TEMPORAL_INITIAL_ADMIN_EMAIL}/$(escape_sed "$TEMPORAL_INITIAL_ADMIN_EMAIL")/g" "$rendered"
sed -i "s/\${TEMPORAL_INITIAL_ADMIN_PASSWORD}/$(escape_sed "$TEMPORAL_INITIAL_ADMIN_PASSWORD")/g" "$rendered"

exec /opt/keycloak/bin/kc.sh "$@"
