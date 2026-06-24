#!/usr/bin/env bash

ENV_GUARD_PLACEHOLDER_REGEX='(^$|replace-me|example\.com|xxxxxxxx|123456789012|my-eks-cluster|owner/repo)'

env_guard_check_required() {
  local missing=()
  local name

  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      missing+=("$name")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'missing required environment variables:\n' >&2
    printf '  - %s\n' "${missing[@]}" >&2
    return 2
  fi
}

env_guard_check_real_values() {
  local invalid=()
  local name
  local value

  for name in "$@"; do
    value="${!name:-}"
    if [[ "$value" =~ $ENV_GUARD_PLACEHOLDER_REGEX ]]; then
      invalid+=("$name")
    fi
  done

  if [[ ${#invalid[@]} -gt 0 ]]; then
    printf 'refusing placeholder values for environment variables:\n' >&2
    printf '  - %s\n' "${invalid[@]}" >&2
    return 2
  fi
}
