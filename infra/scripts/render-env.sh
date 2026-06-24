#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <template-file> <output-file>" >&2
  exit 2
fi

template_file="$1"
output_file="$2"

mkdir -p "$(dirname "$output_file")"

perl -0pe 's/\$\{([A-Z0-9_]+)\}/exists $ENV{$1} ? $ENV{$1} : die "missing env var: $1\n"/ge' \
  "$template_file" > "$output_file"
