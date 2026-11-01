#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$root/config/upstream_repositories.tsv"
destination="${UPSTREAM:-$root/upstream}"
selection="${1:-${FETCH_SET:-native}}"
retries="${FETCH_RETRIES:-3}"
timeout_seconds="${FETCH_TIMEOUT_SECONDS:-60}"
mkdir -p "$destination"
wanted() {
    local name="$1" group="$2"
    case "$selection" in
        all) return 0 ;;
        native) [[ "$group" == native ]] ;;
        opfb) [[ "$group" == opfb ]] ;;
        reference) [[ "$group" == reference ]] ;;
        *) [[ "$selection" == "$name" ]] ;;
    esac
}
retry() {
    local attempt=1
    while ! timeout "$timeout_seconds" "$@"; do
        if ((attempt >= retries)); then return 1; fi
        echo "Retry $attempt/$retries: $*" >&2
        attempt=$((attempt+1))
    done
}
while IFS=$'\t' read -r name group url ref; do
    [[ -n "$name" && "${name:0:1}" != "#" ]] || continue
    wanted "$name" "$group" || continue
    repo="$destination/$name"
    if [[ ! -d "$repo/.git" ]]; then
        echo "Cloning $name"
        retry git clone --filter=blob:none --no-checkout "$url" "$repo" || {
            echo "ERROR: clone failed for $name; rerun this exact stage to resume" >&2; exit 5;
        }
    fi
    git -C "$repo" remote set-url origin "$url"
    retry git -C "$repo" fetch --depth=1 origin "$ref" || {
        echo "ERROR: fetch failed for $name ref $ref" >&2; exit 5;
    }
    git -C "$repo" checkout --detach FETCH_HEAD
    git -C "$repo" submodule update --init --recursive
    printf '%s\t%s\t%s\n' "$name" "$(git -C "$repo" rev-parse HEAD)" "$url"
done < "$manifest"
echo "Selected references are available under $destination"

