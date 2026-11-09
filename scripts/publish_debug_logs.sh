#!/usr/bin/env bash
# Copy selected stage logs and status into a small, reviewable Git snapshot.
# Deliberate user action only: logs can expose local paths and hostnames.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
branch="$(git branch --show-current)"
if [[ "$branch" != arena/* && "${PUBLISH_ALLOW_ANY_BRANCH:-0}" != "1" ]]; then
    echo "ERROR: debug-log publication is allowed only from an Arena working branch, not ${branch:-detached HEAD}." >&2
    echo "On a local checkout, rerun as: PUBLISH_ALLOW_ANY_BRANCH=1 make publish-debug-logs" >&2
    exit 2
fi
flow="${CHANNELIZER_FLOW:-opfb}"
case "$flow" in opfb|matlab_hdl|model_composer|external) ;; *) echo 'Invalid CHANNELIZER_FLOW' >&2; exit 2 ;; esac
build="${BUILD:-$root/build}"
build="$(realpath -m -- "$build")"
run_id="$(date -u +%Y%m%dT%H%M%SZ)"
out="docs/debug-logs/${run_id}-${flow}"
mkdir -p "$(dirname "$out")"
mkdir "$out"

# Keep this allowlist focused on stage progress and the failure boundary.
stages=(
    mts_base step00_preflight step01_fetch_references
    step02_hls_covariance step03_hls_spectrum step04_hls_candidate
    step04_hls_beam step05_hls_repack step05_channelizer
    step05_subband_bridge step05_hls_phase_interf step06_collect_ip step07_vivado_project
    step08_vivado_integrate step09_vivado_validate step10_synth
    step11_impl step12_bitstream step13_export_xsa
    step14_hil_vectors step15_package
)
found=0
for stage in "${stages[@]}"; do
    log="$build/logs/$stage.log"
    if [[ -s "$log" ]]; then
        size=$(wc -c < "$log")
        if (( size > 15000000 )); then
            {
                head -c 2000000 "$log"
                printf '\n\n... [TRUNCATED OVERSIZED LOG (%s bytes total); SHOWING HEAD 2MB + TAIL 4MB] ...\n\n' "$size"
                tail -c 4000000 "$log"
            } > "$out/$(basename "$log")"
            echo "Truncated oversized log ($size bytes) into $out/$(basename "$log")"
        else
            cp -- "$log" "$out/"
        fi
        found=$((found + 1))
    fi
done

# Optional V06 gate artifacts are supplied only by the dedicated wrapper.
# Keep the resolved paths inside BUILD and copy just the transcript/report,
# never the generated HDL tree.
copy_gate_artifact() {
    local source_path="$1"
    local source_real size
    source_real="$(realpath -m -- "$source_path")"
    case "$source_real" in
        "$build"/*) ;;
        *) echo "ERROR: refusing channelizer artifact outside BUILD: $source_path" >&2; exit 2 ;;
    esac
    if [[ -s "$source_real" ]]; then
        size=$(wc -c < "$source_real")
        if (( size > 15000000 )); then
            echo "ERROR: refusing oversized channelizer artifact (>15 MB): $source_real" >&2
            exit 2
        fi
        cp -- "$source_real" "$out/$(basename "$source_real")"
        found=$((found + 1))
        echo "Included channelizer gate artifact: $(basename "$source_real")"
    else
        printf 'Expected channelizer gate artifact was not generated: %s\n' "$source_real" > "$out/channelizer_gate_report_missing.txt"
        found=$((found + 1))
    fi
}
if [[ -n "${CHANNELIZER_GATE_LOG:-}" ]]; then
    copy_gate_artifact "$CHANNELIZER_GATE_LOG"
fi
if [[ -n "${CHANNELIZER_GATE_REPORT:-}" ]]; then
    copy_gate_artifact "$CHANNELIZER_GATE_REPORT"
fi

if (( found == 0 )); then
    echo "ERROR: no stage logs or channelizer gate artifacts found under $build" >&2
    exit 2
fi
# The MTS base (stage V03) runs Vivado outside build/logs; its transcript is the only
# record of that build, so publish it when it exists.
for base_log in \
    "$build/mts_base_src_2023p2/boards/ZCU208/build_mts/vivado.log" \
    "$build/mts_base_src_2023p2/boards/ZCU208/build_mts/vivado.jou" ; do
    if [[ -s "$base_log" ]]; then
        size=$(wc -c < "$base_log")
        dest="$out/mts_base_$(basename "$base_log")"
        if (( size > 15000000 )); then
            { head -c 2000000 "$base_log"; printf '\n... [TRUNCATED %s bytes] ...\n' "$size"; tail -c 4000000 "$base_log"; } > "$dest"
        else
            cp -- "$base_log" "$dest"
        fi
        found=$((found + 1))
        echo "Included MTS base transcript: $(basename "$base_log") ($size bytes)"
    fi
done

for extra_report in \
    step08_base_bd_inventory.txt \
    v06_gate5_package.rpt \
    doa_subband_bridge_4ch_package.rpt \
    v07_bd_integration.rpt \
    v07_wideband_df_quick.txt \
    v07_gate2_csynth.rpt \
    v07_gate2_csynth_design_size.rpt \
    v07_gate2_csynth_design_utilization.rpt \
    v07_gate2_csynth_design_timing.rpt \
    v07_gate2_csim.log \
    v07_gate3_ooc_synthesis.rpt \
    v07_gate3_utilization.rpt \
    v07_gate3_timing_summary.rpt \
    v07_gate3_timing_paths.rpt \
    v07_gate3_clocks.rpt \
    v07_gate3_check_timing.rpt \
    doa_address_map.txt \
    ip_status.txt \
    validation_messages.txt \
    post_synth_utilization.rpt \
    post_synth_timing.rpt \
    post_route_utilization.rpt \
    post_route_utilization_hierarchical.rpt \
    post_route_timing.rpt \
    post_route_drc.rpt \
    route_status.rpt \
    timing_gate.txt; do
    extra_path="$build/output/$extra_report"
    if [[ -s "$extra_path" && ! -f "$out/$extra_report" ]]; then
        size=$(wc -c < "$extra_path")
        if (( size <= 15000000 )); then
            cp -- "$extra_path" "$out/"
            echo "Included build output report: $extra_report"
        fi
    fi
done
{
    printf 'Captured UTC: %s\n' "$(date -u +%FT%TZ)"
    printf 'Source commit: %s\n' "$(git rev-parse HEAD)"
    printf 'Branch: %s\n' "$branch"
    printf 'Requested channelizer flow: %s\n' "$flow"
    if [[ -n "${CHANNELIZER_GATE:-}" ]]; then
        printf 'Requested V06 channelizer gate: %s\n' "$CHANNELIZER_GATE"
    fi
    printf 'BUILD: %s\n\n' "$build"
    printf '%-28s %-12s %s\n' STAGE STATUS FINISHED_UTC
    for stage in "${stages[@]}"; do
        stamp="$build/.stamps/$stage.done"
        log="$build/logs/$stage.log"
        if [[ -f "$stamp" ]]; then
            finished="$(sed -n 's/^finished_utc=//p' "$stamp" | tail -n 1)"
            printf '%-28s %-12s %s\n' "$stage" PASS "$finished"
        elif [[ -f "$log" ]]; then
            printf '%-28s %-12s %s\n' "$stage" FAILED/INCOMPLETE "see $stage.log"
        else
            printf '%-28s %-12s %s\n' "$stage" NOT-RUN '-'
        fi
    done
} > "$out/progress.txt"

echo "Debug snapshot: $out"
echo "Copied $found stage log(s) plus progress.txt. Review these files before publishing; logs may contain usernames, hostnames, and local paths."
git add -- "$out"
git diff --cached --stat -- "$out"
if [[ "${EVIDENCE_YES:-0}" != 1 ]]; then
    if [[ "${EVIDENCE_PUSH:-1}" == 0 ]]; then
        prompt='Commit this snapshot locally? Push it later with GitHub Desktop. [y/N] '
    else
        prompt='Commit and push this debug snapshot on the current branch? [y/N] '
    fi
    read -r -p "$prompt" answer
    [[ "$answer" == y || "$answer" == Y ]] || {
        git reset -q -- "$out"
        echo "Not pushed. Snapshot remains at $out for review."
        exit 0
    }
fi
if ! git diff --cached --quiet -- "$out"; then
    git commit -m "Add Vivado debug logs ($(date -u +%F))" --only -- "$out"
else
    echo 'No debug-log changes to commit.'
fi
if [[ "${EVIDENCE_PUSH:-1}" == 0 ]]; then
    echo 'Debug logs committed locally; push was disabled by EVIDENCE_PUSH=0.'
    exit 0
fi
git push origin "$branch"
printf '\nPublished debug snapshot: %s\nCommit: ' "$out"
git rev-parse HEAD
