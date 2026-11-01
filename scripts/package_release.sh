#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$RELEASE_DIR"
archive="$RELEASE_DIR/${PROJECT_NAME}_artifacts.tar.gz"
items=(docs config build/logs build/.stamps)
[[ -d build/output ]] && items+=(build/output)
[[ -d "$HIL_OUTPUT_DIR" ]] && items+=("${HIL_OUTPUT_DIR#"$PWD/"}")
tar -czf "$archive" "${items[@]}"
sha256sum "$archive" > "$archive.sha256"
echo "Packaged $archive"

