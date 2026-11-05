#!/usr/bin/env bash
# Run an ordered sequence of Make stages, stopping on the first failure, and
# always snapshot stage logs + reports into docs/debug-logs/ (local commit).
set -uo pipefail
if (( $# == 0 )); then
    echo "Usage: make debug-stages STEPS=\"step05_channelizer step05_subband_bridge ...\"" >&2
    exit 2
fi

overall_rc=0
for step in "$@"; do
    echo
    echo "===== Running $step ====="
    set +e
    make --no-print-directory stage STEP="$step"
    overall_rc=$?
    set -e
    if (( overall_rc != 0 )); then
        echo "Stage $step exited with code=$overall_rc; stopping sequence to snapshot logs."
        break
    fi
done

echo "Sequence exit code=$overall_rc; capturing build logs and reports now."
EVIDENCE_PUSH=0 bash scripts/publish_debug_logs.sh
publish_rc=$?
if (( publish_rc != 0 )); then
    exit "$publish_rc"
fi
exit "$overall_rc"
