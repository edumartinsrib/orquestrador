#!/usr/bin/env bash
set -euo pipefail

: "${KCADM:=/opt/keycloak/bin/kcadm.sh}"
: "${KEYCLOAK_ADMIN_SERVER:=http://localhost:8080}"
: "${TEMPORAL_AUTH_REALM:=temporal}"
: "${TEMPORAL_AUTH_CLIENT_NAME:=Temporal UI}"

required=(
  KC_BOOTSTRAP_ADMIN_USERNAME
  KC_BOOTSTRAP_ADMIN_PASSWORD
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

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

realm_json="$tmp_dir/realm.json"
client_json="$tmp_dir/client.json"
user_json="$tmp_dir/user.json"

realm="$(json_escape "$TEMPORAL_AUTH_REALM")"
client_id="$(json_escape "$TEMPORAL_AUTH_CLIENT_ID")"
client_name="$(json_escape "$TEMPORAL_AUTH_CLIENT_NAME")"
client_secret="$(json_escape "$TEMPORAL_AUTH_CLIENT_SECRET")"
ui_url="$(json_escape "${TEMPORAL_UI_PUBLIC_URL%/}")"
redirect_uri="$(json_escape "${TEMPORAL_UI_PUBLIC_URL%/}/auth/sso/callback")"
admin_username="$(json_escape "$TEMPORAL_INITIAL_ADMIN_USERNAME")"
admin_email="$(json_escape "$TEMPORAL_INITIAL_ADMIN_EMAIL")"

cat >"$realm_json" <<EOF
{
  "realm": "$realm",
  "enabled": true,
  "displayName": "Temporal",
  "registrationAllowed": false,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "sslRequired": "external"
}
EOF

cat >"$client_json" <<EOF
{
  "clientId": "$client_id",
  "name": "$client_name",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": false,
  "bearerOnly": false,
  "standardFlowEnabled": true,
  "implicitFlowEnabled": false,
  "directAccessGrantsEnabled": false,
  "serviceAccountsEnabled": false,
  "clientAuthenticatorType": "client-secret",
  "secret": "$client_secret",
  "redirectUris": [
    "$redirect_uri"
  ],
  "webOrigins": [
    "$ui_url"
  ],
  "attributes": {
    "post.logout.redirect.uris": "$ui_url/*"
  },
  "defaultClientScopes": [
    "web-origins",
    "acr",
    "profile",
    "roles",
    "email"
  ],
  "optionalClientScopes": [
    "address",
    "phone",
    "offline_access",
    "microprofile-jwt"
  ]
}
EOF

cat >"$user_json" <<EOF
{
  "username": "$admin_username",
  "email": "$admin_email",
  "emailVerified": true,
  "enabled": true,
  "firstName": "Temporal",
  "lastName": "Admin"
}
EOF

"$KCADM" config credentials \
  --server "$KEYCLOAK_ADMIN_SERVER" \
  --realm master \
  --user "$KC_BOOTSTRAP_ADMIN_USERNAME" \
  --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null

if "$KCADM" get "realms/$TEMPORAL_AUTH_REALM" >/dev/null 2>&1; then
  "$KCADM" update "realms/$TEMPORAL_AUTH_REALM" -f "$realm_json" >/dev/null
else
  "$KCADM" create realms -f "$realm_json" >/dev/null
fi

for role in temporal-admin temporal-viewer; do
  if ! "$KCADM" get "roles/$role" -r "$TEMPORAL_AUTH_REALM" >/dev/null 2>&1; then
    "$KCADM" create roles -r "$TEMPORAL_AUTH_REALM" \
      -s "name=$role" \
      -s "description=Temporal $role users" >/dev/null
  fi
done

client_uuid="$(
  "$KCADM" get clients \
    -r "$TEMPORAL_AUTH_REALM" \
    -q "clientId=$TEMPORAL_AUTH_CLIENT_ID" \
    --fields id \
    --format csv \
    --noquotes 2>/dev/null \
    | sed '/^[[:space:]]*$/d' \
    | head -n 1 \
    | tr -d '\r'
)"

if [[ -n "$client_uuid" ]]; then
  "$KCADM" update "clients/$client_uuid" -r "$TEMPORAL_AUTH_REALM" -f "$client_json" >/dev/null
else
  "$KCADM" create clients -r "$TEMPORAL_AUTH_REALM" -f "$client_json" >/dev/null
fi

user_id="$(
  "$KCADM" get users \
    -r "$TEMPORAL_AUTH_REALM" \
    -q "username=$TEMPORAL_INITIAL_ADMIN_USERNAME" \
    --fields id \
    --format csv \
    --noquotes 2>/dev/null \
    | sed '/^[[:space:]]*$/d' \
    | head -n 1 \
    | tr -d '\r'
)"

if [[ -n "$user_id" ]]; then
  "$KCADM" update "users/$user_id" -r "$TEMPORAL_AUTH_REALM" -f "$user_json" >/dev/null
else
  "$KCADM" create users -r "$TEMPORAL_AUTH_REALM" -f "$user_json" >/dev/null
fi

"$KCADM" set-password \
  -r "$TEMPORAL_AUTH_REALM" \
  --username "$TEMPORAL_INITIAL_ADMIN_USERNAME" \
  --new-password "$TEMPORAL_INITIAL_ADMIN_PASSWORD" >/dev/null

"$KCADM" add-roles \
  -r "$TEMPORAL_AUTH_REALM" \
  --uusername "$TEMPORAL_INITIAL_ADMIN_USERNAME" \
  --rolename temporal-admin >/dev/null

echo "Temporal Keycloak realm reconciled."
