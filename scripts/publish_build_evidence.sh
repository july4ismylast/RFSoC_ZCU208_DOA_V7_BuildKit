#!/usr/bin/env bash
# Publish small, explicitly selected build reports; never stage build trees.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
branch="$(git branch --show-current)"
if [[ "$branch" != arena/* ]]; then
    echo "ERROR: evidence publication is allowed only from an Arena working branch, not $branch." >&2
    exit 2
fi
flow="${CHANNELIZER_FLOW:-opfb}"
case "$flow" in opfb|matlab_hdl|model_composer|external) ;; *) echo 'Invalid CHANNELIZER_FLOW' >&2; exit 2 ;; esac
out="docs/evidence/$(date +%F)-$flow"
build="${BUILD:-$PWD/build}"
ip_repo="${IP_REPO:-$build/ip_repo}"

# The OPFB route check is an OOC physical screen, not the production build or
# bitstream flow. Do not publish partial/stale-looking results when Vivado
# stopped before routing, DRC, report generation, or checkpoint save completed.
if [[ "$flow" == opfb ]]; then
    route_log="$build/logs/v06_opfb_route.log"
    drc_report="$build/output/v06_opfb_routed_drc.rpt"
    status_report="$build/output/v06_opfb_route_status.rpt"
    widths_report="$build/output/v06_opfb_interface_widths.rpt"
    for required in "$route_log" "$drc_report" "$status_report" "$widths_report"; do
        if [[ ! -s "$required" ]]; then
            echo "ERROR: required OPFB completion evidence is missing or empty: $required" >&2
            exit 2
        fi
    done
    for marker in \
        'route_design completed successfully' \
        'report_timing_summary:' \
        'report_drc completed successfully' \
        'Physical screen reports written.' \
        'Exiting Vivado at'; do
        if ! grep -Fq "$marker" "$route_log"; then
            echo "ERROR: OPFB route log lacks completion marker: $marker" >&2
            echo 'Refusing to publish incomplete OPFB evidence.' >&2
            exit 2
        fi
    done
    grep -Fq 'Design State : Fully Routed' "$drc_report" || {
        echo 'ERROR: OPFB DRC report does not identify a fully routed design.' >&2; exit 2;
    }
    grep -Eq '# of nets with routing errors[. ]*:[[:space:]]*0([[:space:]]|$)' "$status_report" || {
        echo 'ERROR: OPFB route-status report is missing or reports routing errors.' >&2; exit 2;
    }
    grep -Fq 'istream_V_0 TDATA_NUM_BYTES=16' "$widths_report" &&
        grep -Fq 'qstream_V_0 TDATA_NUM_BYTES=16' "$widths_report" &&
        grep -Fq 'output_r_0 TDATA_NUM_BYTES=64' "$widths_report" || {
        echo 'ERROR: OPFB interface-width report is missing expected 16/16/64-byte widths.' >&2; exit 2;
    }
    echo 'OPFB evidence passed completion checks (OOC physical route only; no bitstream implied).'
fi
# Refuse to accidentally commit already-staged source or generated files.
while IFS= read -r -d '' file; do
    case "$file" in "$out"/*) ;; *) echo "ERROR: unrelated staged file: $file. Unstage it first." >&2; exit 2 ;; esac
done < <(git diff --cached --name-only -z)
mkdir -p "$out"
files=(
    "$build/logs/step05_channelizer.log"
    "$build/logs/step06_collect_ip.log"
    "$build/logs/step07_vivado_project.log"
    "$build/logs/v06_opfb_ooc.log"
    "$build/logs/v06_opfb_route.log"
    "$build/output/v06_opfb_routed_utilization.rpt"
    "$build/output/v06_opfb_routed_utilization_hierarchical.rpt"
    "$build/output/v06_opfb_routed_timing.rpt"
    "$build/output/v06_opfb_route_status.rpt"
    "$build/output/v06_opfb_routed_drc.rpt"
    "$build/output/v06_opfb_interface_widths.rpt"
    "$build/output/v06_opfb_ooc_utilization.rpt"
    "$build/output/v06_opfb_ooc_utilization_hierarchical.rpt"
    "$build/output/v06_opfb_ooc_timing.rpt"
    "$build/output/opfb_work_project_ip_status_after_repair.rpt"
    "$ip_repo/ip_manifest.tsv"
    "$build/output/v06_mts_base_utilization.rpt"
    "$build/output/v06_mts_base_utilization_detailed.rpt"
    "$build/output/v06_mts_base_utilization_hierarchical.rpt"
)
for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "WARN: missing $file"
        continue
    fi
    if (( $(wc -c < "$file") > 10000000 )); then
        echo "ERROR: report exceeds 10 MB: $file" >&2
        exit 2
    fi
    cp -- "$file" "$out/"
done
{
    printf 'Source commit: '; git rev-parse HEAD
    printf 'Collection time UTC: '; date -u +%FT%TZ
    printf 'Requested channelizer flow: %s\n' "$flow"
    printf 'BUILD=%s\nIP_REPO=%s\n' "$build" "$ip_repo"
    printf '\nConfiguration defaults (command-line overrides may differ):\n'
    grep -nE '^(PART|BOARD_PART|BASE_KIND|CHANNELIZER_|OPFB_|IPVER_)' config.mk || true
} > "$out/build_context.txt"
echo "Evidence folder: $out"
echo 'Reports can contain local paths and hostnames. Review before publishing.'
git add -- "$out"
git diff --cached --stat
if [[ "${EVIDENCE_YES:-0}" != 1 ]]; then
    read -r -p 'Commit and push these evidence files? [y/N] ' answer
    [[ "$answer" == y || "$answer" == Y ]] || { echo 'Not pushed; evidence remains staged.'; exit 0; }
fi
if ! git diff --cached --quiet; then
    git commit -m "Add $flow build evidence ($(date +%F))" --only -- "$out"
else
    echo 'No evidence changes to commit; retrying push if needed.'
fi
if [[ "${EVIDENCE_PUSH:-1}" == 0 ]]; then
    echo 'Evidence committed locally. Click Push origin in GitHub Desktop.'
    git rev-parse HEAD
    exit 0
fi
# Never force-push or push to master. A rejected push remains a visible failure.
git push origin "${branch}"
printf '\nPublished commit: '; git rev-parse HEAD
