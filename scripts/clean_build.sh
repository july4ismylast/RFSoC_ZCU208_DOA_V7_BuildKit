#!/usr/bin/env bash
set -euo pipefail
build="$1"; ip_repo="$2"
[[ -n "$build" && "$build" != "/" && "$build" != "$HOME" ]] || { echo "Unsafe BUILD path" >&2; exit 2; }
[[ -n "$ip_repo" && "$ip_repo" != "/" && "$ip_repo" != "$HOME" ]] || { echo "Unsafe IP_REPO path" >&2; exit 2; }
rm -rf "$build"
if [[ "$ip_repo" != "$build"/* ]]; then rm -rf "$ip_repo"; fi
echo "Removed build products under $build"

