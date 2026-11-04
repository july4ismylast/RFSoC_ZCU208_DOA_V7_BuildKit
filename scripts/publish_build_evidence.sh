#!/usr/bin/env bash
# Publish small, explicitly selected build reports; never stage build trees.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
branch='arena/752990a5-rfsoc-zcu208-doa-v7-buildkit'
if [[ "$(git branch --show-current)" != "$branch" ]]; then
    echo "ERROR: run this on $branch, not $(git branch --show-current)." >&2
    exit 2
fi
flow="${CHANNELIZER_FLOW:-opfb}"
case "$flow" in opfb|matlab_hdl|model_composer|external) ;; *) echo 'Invalid CHANNELIZER_FLOW' >&2; exit 2 ;; esac
out="docs/evidence/$(date +%F)-$flow"
build="${BUILD:-$PWD/build}"
ip_repo="${IP_REPO:-$build/ip_repo}"
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
