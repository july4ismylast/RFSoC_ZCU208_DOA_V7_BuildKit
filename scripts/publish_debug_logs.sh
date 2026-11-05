#!/usr/bin/env bash
# Copy selected stage logs and status into a small, reviewable Git snapshot.
# Deliberate user action only: logs can expose local paths and hostnames.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
branch="$(git branch --show-current)"
if [[ "$branch" != arena/* ]]; then
    echo "ERROR: debug-log publication is allowed only from an Arena working branch, not $branch." >&2
    exit 2
fi
flow="${CHANNELIZER_FLOW:-opfb}"
case "$flow" in opfb|matlab_hdl|model_composer|external) ;; *) echo 'Invalid CHANNELIZER_FLOW' >&2; exit 2 ;; esac
build="${BUILD:-$root/build}"
run_id="$(date -u +%Y%m%dT%H%M%SZ)"
out="docs/debug-logs/${run_id}-${flow}"
mkdir -p "$(dirname "$out")"
mkdir "$out"

# Keep this allowlist focused on stage progress and the failure boundary.
stages=(
    step00_preflight step01_fetch_references
    step02_hls_covariance step03_hls_spectrum step04_hls_candidate
    step04_hls_beam step05_hls_repack step05_channelizer
    step06_collect_ip step07_vivado_project step08_vivado_integrate
    step09_vivado_validate step10_synth step11_impl step12_bitstream
    step13_export_xsa step14_hil_vectors step15_package
)
found=0
for stage in "${stages[@]}"; do
    log="$build/logs/$stage.log"
    if [[ -s "$log" ]]; then
        size=$(wc -c < "$log")
        if (( size > 15000000 )); then
            echo "ERROR: refusing oversized log (>15 MB): $log" >&2
            exit 2
        fi
        cp -- "$log" "$out/"
        found=$((found + 1))
    fi
done
if (( found == 0 )); then
    echo "ERROR: no stage logs found under $build/logs" >&2
    exit 2
fi
inventory="$build/output/step08_base_bd_inventory.txt"
if [[ -s "$inventory" ]]; then
    size=$(wc -c < "$inventory")
    if (( size > 15000000 )); then
        echo "ERROR: refusing oversized BD inventory (>15 MB): $inventory" >&2
        exit 2
    fi
    cp -- "$inventory" "$out/"
    echo 'Included Vivado base-BD inventory.'
fi
{
    printf 'Captured UTC: %s\n' "$(date -u +%FT%TZ)"
    printf 'Source commit: %s\n' "$(git rev-parse HEAD)"
    printf 'Branch: %s\n' "$branch"
    printf 'Requested channelizer flow: %s\n' "$flow"
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
    read -r -p 'Commit and push this debug snapshot on the current branch? [y/N] ' answer
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
