#!/usr/bin/env bash
# Run one Make stage, then snapshot/publish its logs regardless of stage result.
set -uo pipefail
step="${1:-}"
if [[ -z "$step" ]]; then
    echo "Usage: make debug-stage STEP=stepNN_name" >&2
    exit 2
fi

set +e
make --no-print-directory stage STEP="$step"
stage_rc=$?
set -e

echo "Stage exit code=$stage_rc; capturing build logs now."
EVIDENCE_PUSH=0 bash scripts/publish_debug_logs.sh
publish_rc=$?
if (( publish_rc != 0 )); then
    exit "$publish_rc"
fi
exit "$stage_rc"
