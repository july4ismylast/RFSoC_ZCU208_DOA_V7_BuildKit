#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 3 ]]; then echo "usage: $0 <source_repo> <dest_ip_repo> <name>" >&2; exit 2; fi
SRC="$(realpath "$1")"; DST="$(realpath -m "$2")"; NAME="$3"
mapfile -t comps < <(find "$SRC" -name component.xml -type f | sort)
if [[ ${#comps[@]} -eq 0 ]]; then
  echo "No packaged Vivado IP (component.xml) found under $SRC" >&2
  echo "Inspect the repo; it may require HLS/System Generator before packaging." >&2
  exit 3
fi
printf 'Found packaged IP candidates:\n'; printf '  %s\n' "${comps[@]}"
# Choose the first candidate unless COMPONENT_XML is supplied.
COMP="${COMPONENT_XML:-${comps[0]}}"
mkdir -p "$DST/$NAME"
cp -a "$(dirname "$COMP")"/. "$DST/$NAME"/
echo "Imported $(dirname "$COMP") -> $DST/$NAME"
