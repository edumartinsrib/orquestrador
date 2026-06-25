#!/usr/bin/env bash
set -Eeuo pipefail

parser="/opt/devconsole/parse_database_url.py"

log() {
  printf '[devconsole] %s\n' "$*"
}

is_true() {
  case "${1:-}" in
    true|TRUE|True|1|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

require_env() {
  local missing=0
  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      printf '[devconsole] missing required environment variable: %s\n' "$name" >&2
      missing=1
    fi
  done
  return "$missing"
}

load_database_url() {
  local mode="$1"
  local url="$2"

  set -a
  # The parser shell-quotes assignments so passwords with special characters survive eval.
  eval "$("$parser" "$mode" "$url")"
  set +a
}

normalize_env() {
  if [[ -n "${TEMPORAL_DATABASE_URL:-}" ]]; then
    load_database_url default "$TEMPORAL_DATABASE_URL"
  elif [[ -n "${DATABASE_URL:-}" ]]; then
    load_database_url default "$DATABASE_URL"
  fi

  : "${POSTGRES_SEEDS:=${TEMPORAL_DB_HOST:-}}"
  : "${DB_PORT:=${TEMPORAL_DB_PORT:-5432}}"
  : "${DBNAME:=${TEMPORAL_DB_NAME:-temporal}}"
  : "${POSTGRES_USER:=${TEMPORAL_DB_USER:-}}"
  : "${POSTGRES_PWD:=${TEMPORAL_DB_PASSWORD:-}}"
  : "${DB:=postgres12}"

  if [[ -n "${TEMPORAL_VISIBILITY_DATABASE_URL:-}" ]]; then
    load_database_url visibility "$TEMPORAL_VISIBILITY_DATABASE_URL"
  fi

  : "${VISIBILITY_POSTGRES_SEEDS:=${TEMPORAL_VISIBILITY_DB_HOST:-$POSTGRES_SEEDS}}"
  : "${VISIBILITY_DB_PORT:=${TEMPORAL_VISIBILITY_DB_PORT:-$DB_PORT}}"
  : "${VISIBILITY_DBNAME:=${TEMPORAL_VISIBILITY_DB_NAME:-temporal_visibility}}"
  : "${VISIBILITY_POSTGRES_USER:=${TEMPORAL_VISIBILITY_DB_USER:-$POSTGRES_USER}}"
  : "${VISIBILITY_POSTGRES_PWD:=${TEMPORAL_VISIBILITY_DB_PASSWORD:-$POSTGRES_PWD}}"

  : "${SQL_TLS_ENABLED:=${TEMPORAL_DB_TLS_ENABLED:-false}}"
  : "${SQL_TLS:=$SQL_TLS_ENABLED}"
  : "${BIND_ON_IP:=0.0.0.0}"
  : "${TEMPORAL_ADDRESS:=127.0.0.1:7233}"
  : "${TEMPORAL_NAMESPACE:=default}"
  : "${TEMPORAL_DEFAULT_NAMESPACE:=$TEMPORAL_NAMESPACE}"
  : "${TEMPORAL_UI_ENABLED:=true}"
  : "${TEMPORAL_UI_PORT:=${PORT:-8080}}"
  : "${TEMPORAL_CLOUD_UI:=false}"
  : "${TEMPORAL_SHOW_TEMPORAL_SYSTEM_NAMESPACE:=false}"
  : "${DYNAMIC_CONFIG_FILE_PATH:=/opt/devconsole/dynamicconfig/docker.yaml}"

  if [[ -n "${TEMPORAL_UI_PUBLIC_URL:-}" && -z "${TEMPORAL_AUTH_CALLBACK_URL:-}" ]]; then
    TEMPORAL_AUTH_CALLBACK_URL="${TEMPORAL_UI_PUBLIC_URL%/}/auth/sso/callback"
  fi

  require_env POSTGRES_SEEDS DB_PORT DBNAME POSTGRES_USER POSTGRES_PWD \
    VISIBILITY_POSTGRES_SEEDS VISIBILITY_DB_PORT VISIBILITY_DBNAME \
    VISIBILITY_POSTGRES_USER VISIBILITY_POSTGRES_PWD

  export DB DBNAME POSTGRES_SEEDS DB_PORT POSTGRES_USER POSTGRES_PWD
  export VISIBILITY_DBNAME VISIBILITY_POSTGRES_SEEDS VISIBILITY_DB_PORT
  export VISIBILITY_POSTGRES_USER VISIBILITY_POSTGRES_PWD
  export SQL_TLS SQL_TLS_ENABLED BIND_ON_IP TEMPORAL_ADDRESS TEMPORAL_NAMESPACE
  export TEMPORAL_DEFAULT_NAMESPACE TEMPORAL_UI_ENABLED TEMPORAL_UI_PORT
  export TEMPORAL_CLOUD_UI TEMPORAL_SHOW_TEMPORAL_SYSTEM_NAMESPACE
  export TEMPORAL_AUTH_CALLBACK_URL DYNAMIC_CONFIG_FILE_PATH
}

wait_for_port() {
  local host="$1"
  local port="$2"
  local label="$3"
  local max_attempts="${TEMPORAL_HEALTH_CHECK_MAX_ATTEMPTS:-60}"
  local sleep_seconds="${TEMPORAL_HEALTH_CHECK_SLEEP_SECONDS:-5}"
  local attempt=1

  log "waiting for ${label} at ${host}:${port}"
  until nc -z -w 10 "$host" "$port"; do
    if (( attempt >= max_attempts )); then
      printf '[devconsole] %s did not become available at %s:%s\n' "$label" "$host" "$port" >&2
      return 1
    fi
    log "${label} not ready yet (${attempt}/${max_attempts})"
    attempt=$((attempt + 1))
    sleep "$sleep_seconds"
  done
}

temporal_sql_tool() {
  local host="$1"
  local port="$2"
  local user="$3"
  local password="$4"
  local database="$5"
  shift 5

  SQL_PASSWORD="$password" SQL_TLS="$SQL_TLS" temporal-sql-tool \
    --plugin postgres12 \
    --ep "$host" \
    --port "$port" \
    --user "$user" \
    --db "$database" \
    "$@"
}

setup_database_schema() {
  if is_true "${TEMPORAL_SKIP_SCHEMA_SETUP:-false}"; then
    log "skipping Temporal schema setup because TEMPORAL_SKIP_SCHEMA_SETUP=true"
    return 0
  fi

  wait_for_port "$POSTGRES_SEEDS" "$DB_PORT" "PostgreSQL default store"
  if [[ "$VISIBILITY_POSTGRES_SEEDS:$VISIBILITY_DB_PORT" != "$POSTGRES_SEEDS:$DB_PORT" ]]; then
    wait_for_port "$VISIBILITY_POSTGRES_SEEDS" "$VISIBILITY_DB_PORT" "PostgreSQL visibility store"
  fi

  log "ensuring Temporal default schema in database '$DBNAME'"
  temporal_sql_tool "$POSTGRES_SEEDS" "$DB_PORT" "$POSTGRES_USER" "$POSTGRES_PWD" "$DBNAME" create || true
  temporal_sql_tool "$POSTGRES_SEEDS" "$DB_PORT" "$POSTGRES_USER" "$POSTGRES_PWD" "$DBNAME" setup-schema -v 0.0 || true
  temporal_sql_tool "$POSTGRES_SEEDS" "$DB_PORT" "$POSTGRES_USER" "$POSTGRES_PWD" "$DBNAME" update-schema \
    -d /etc/temporal/schema/postgresql/v12/temporal/versioned

  log "ensuring Temporal visibility schema in database '$VISIBILITY_DBNAME'"
  temporal_sql_tool "$VISIBILITY_POSTGRES_SEEDS" "$VISIBILITY_DB_PORT" "$VISIBILITY_POSTGRES_USER" "$VISIBILITY_POSTGRES_PWD" "$VISIBILITY_DBNAME" create || true
  temporal_sql_tool "$VISIBILITY_POSTGRES_SEEDS" "$VISIBILITY_DB_PORT" "$VISIBILITY_POSTGRES_USER" "$VISIBILITY_POSTGRES_PWD" "$VISIBILITY_DBNAME" setup-schema -v 0.0 || true
  temporal_sql_tool "$VISIBILITY_POSTGRES_SEEDS" "$VISIBILITY_DB_PORT" "$VISIBILITY_POSTGRES_USER" "$VISIBILITY_POSTGRES_PWD" "$VISIBILITY_DBNAME" update-schema \
    -d /etc/temporal/schema/postgresql/v12/visibility/versioned
}

wait_for_temporal() {
  local max_attempts="${TEMPORAL_HEALTH_CHECK_MAX_ATTEMPTS:-60}"
  local sleep_seconds="${TEMPORAL_HEALTH_CHECK_SLEEP_SECONDS:-5}"
  local attempt=1

  log "waiting for Temporal at $TEMPORAL_ADDRESS"
  until temporal operator cluster health --address "$TEMPORAL_ADDRESS" >/dev/null 2>&1; do
    if (( attempt >= max_attempts )); then
      printf '[devconsole] Temporal did not become healthy at %s\n' "$TEMPORAL_ADDRESS" >&2
      return 1
    fi
    log "Temporal not healthy yet (${attempt}/${max_attempts})"
    attempt=$((attempt + 1))
    sleep "$sleep_seconds"
  done
}

ensure_namespace() {
  local namespace="$TEMPORAL_DEFAULT_NAMESPACE"

  if temporal operator namespace describe -n "$namespace" --address "$TEMPORAL_ADDRESS" >/dev/null 2>&1; then
    log "Temporal namespace '$namespace' already exists"
    return 0
  fi

  log "creating Temporal namespace '$namespace'"
  temporal operator namespace create -n "$namespace" --address "$TEMPORAL_ADDRESS" >/dev/null
}

shutdown() {
  trap - EXIT INT TERM
  log "stopping processes"
  for pid in "${ui_pid:-}" "${server_pid:-}"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done
  wait || true
}

main() {
  normalize_env
  setup_database_schema

  trap shutdown EXIT INT TERM

  log "starting Temporal server"
  /etc/temporal/entrypoint.sh &
  server_pid="$!"

  wait_for_temporal
  ensure_namespace

  if [[ "$TEMPORAL_UI_ENABLED" != "false" ]]; then
    log "starting Temporal UI on port $TEMPORAL_UI_PORT"
    (
      cd /home/ui-server
      ./start-ui-server.sh
    ) &
    ui_pid="$!"
    wait -n "$server_pid" "$ui_pid"
  else
    log "Temporal UI disabled; waiting on Temporal server"
    wait "$server_pid"
  fi
}

main "$@"
