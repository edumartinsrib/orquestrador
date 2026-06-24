#!/bin/sh
set -eu

NAMESPACE="${DEFAULT_NAMESPACE:-default}"
TEMPORAL_ADDRESS="${TEMPORAL_ADDRESS:-temporal:7233}"
MAX_ATTEMPTS="${TEMPORAL_HEALTH_CHECK_MAX_ATTEMPTS:-60}"
SLEEP_SECONDS="${TEMPORAL_HEALTH_CHECK_SLEEP_SECONDS:-5}"

SERVER_HOST="$(echo "$TEMPORAL_ADDRESS" | cut -d: -f1)"
SERVER_PORT="$(echo "$TEMPORAL_ADDRESS" | cut -d: -f2)"

echo "Waiting for Temporal server port ${SERVER_HOST}:${SERVER_PORT}..."
attempt=1
until nc -z -w 10 "$SERVER_HOST" "$SERVER_PORT"; do
  if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
    echo "Temporal server port did not become available."
    exit 1
  fi
  echo "Temporal server port not ready yet ($attempt/$MAX_ATTEMPTS)."
  attempt=$((attempt + 1))
  sleep "$SLEEP_SECONDS"
done

echo "Waiting for Temporal server health..."
attempt=1
until temporal operator cluster health --address "$TEMPORAL_ADDRESS"; do
  if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
    echo "Temporal server did not become healthy."
    exit 1
  fi
  echo "Temporal server not healthy yet ($attempt/$MAX_ATTEMPTS)."
  attempt=$((attempt + 1))
  sleep "$SLEEP_SECONDS"
done

echo "Ensuring namespace '$NAMESPACE' exists..."
attempt=1
while :; do
  if temporal operator namespace describe -n "$NAMESPACE" --address "$TEMPORAL_ADDRESS" >/dev/null 2>&1; then
    echo "Namespace '$NAMESPACE' already exists."
    break
  fi

  if temporal operator namespace create -n "$NAMESPACE" --address "$TEMPORAL_ADDRESS" >/dev/null 2>&1; then
    echo "Namespace '$NAMESPACE' created."
    break
  fi

  if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
    echo "Failed to create namespace '$NAMESPACE'."
    exit 1
  fi

  echo "Namespace operation not ready yet ($attempt/$MAX_ATTEMPTS)."
  attempt=$((attempt + 1))
  sleep "$SLEEP_SECONDS"
done
