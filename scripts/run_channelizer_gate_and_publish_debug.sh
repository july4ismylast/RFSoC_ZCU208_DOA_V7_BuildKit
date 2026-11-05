#!/usr/bin/env bash
# Run one V06 MATLAB-HDL feasibility gate and publish its transcript/report
# even when the gate fails. The snapshot is committed locally for GitHub Desktop.
set -uo pipefail

gate="${1:-}"
case "$gate" in
    probe) report_name="v06_channelizer_probe.rpt" ;;
    probe-transposed) report_name="v06_channelizer_probe_transposed.rpt" ;;
    gate1) report_name="v06_gate1_hdl_generation.rpt" ;;
    gate1-transposed) report_name="v06_gate1_hdl_generation_transposed.rpt" ;;
    gate2) report_name="v06_gate2_ooc_synthesis.rpt" ;;
    gate2r-bram) report_name="v06_gate2r_bram_ooc_synthesis.rpt" ;;
    gate2t-transposed) report_name="v06_gate2t_transposed_ooc_synthesis.rpt" ;;
    gate3-transposed) report_name="v06_gate3_transposed_numerics.rpt" ;;
    *)
        echo "ERROR: unsupported V06 gate '$gate'. Choose probe, probe-transposed, gate1, gate1-transposed, gate2, gate2r-bram, gate2t-transposed, or gate3-transposed." >&2
        exit 2
        ;;
esac

root="$(git rev-parse --show-toplevel)"
cd "$root"
build="$(realpath -m -- "${BUILD:-$root/build}")"
log="$build/logs/v06_${gate}.log"
report="$build/output/$report_name"
mkdir -p "$build/logs"

echo "Running V06 channelizer gate: $gate"
echo "Console transcript: $log"
echo "Gate report: $report"
set +e
make --no-print-directory -C ip/matlab/channelizer_hdl "$gate" 2>&1 | tee "$log"
gate_rc=${PIPESTATUS[0]}
set -e

echo "Gate exit code=$gate_rc; snapshotting transcript and report."
set +e
CHANNELIZER_FLOW=matlab_hdl \
CHANNELIZER_GATE="$gate" \
CHANNELIZER_GATE_LOG="$log" \
CHANNELIZER_GATE_REPORT="$report" \
BUILD="$build" \
EVIDENCE_PUSH=0 \
    bash scripts/publish_debug_logs.sh
publish_rc=$?
set -e
if (( publish_rc != 0 )); then
    exit "$publish_rc"
fi
exit "$gate_rc"
