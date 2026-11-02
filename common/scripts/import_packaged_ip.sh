#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 3 ]]; then echo "usage: $0 <source_repo> <dest_ip_repo> <name>" >&2; exit 2; fi
SRC="$(realpath "$1")"; DST="$(realpath -m "$2")"; NAME="$3"

case "$NAME" in
    ""|"."|".."|*/*)
        echo "ERROR: destination IP name must be one path component, got '$NAME'" >&2
        exit 2
        ;;
esac

mapfile -t comps < <(find "$SRC" -name component.xml -type f | sort)
if [[ ${#comps[@]} -eq 0 ]]; then
  echo "No packaged Vivado IP (component.xml) found under $SRC" >&2
  echo "Inspect the repo; it may require HLS/System Generator before packaging." >&2
  exit 3
fi
printf 'Found packaged IP candidates:\n'; printf '  %s\n' "${comps[@]}"

# Never choose an arbitrary first component from a multi-IP repository.  The
# caller must pin COMPONENT_XML when more than one candidate exists.
if [[ -n "${COMPONENT_XML:-}" ]]; then
    COMP="$(realpath -m "$COMPONENT_XML")"
    found=0
    for candidate in "${comps[@]}"; do
        if [[ "$(realpath "$candidate")" == "$COMP" ]]; then
            found=1
            break
        fi
    done
    if [[ $found -ne 1 ]]; then
        echo "ERROR: COMPONENT_XML is not one of the packaged candidates under $SRC:" >&2
        echo "  $COMP" >&2
        exit 4
    fi
elif [[ ${#comps[@]} -eq 1 ]]; then
    COMP="${comps[0]}"
else
    echo "ERROR: $SRC contains ${#comps[@]} packaged IPs; refusing to guess." >&2
    echo "Set COMPONENT_XML to the exact pinned component.xml for this adapter." >&2
    exit 4
fi

rm -rf "$DST/$NAME"
mkdir -p "$DST/$NAME"
cp -a "$(dirname "$COMP")"/. "$DST/$NAME"/
echo "Imported $(dirname "$COMP") -> $DST/$NAME"
