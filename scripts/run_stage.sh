#!/usr/bin/env bash
set -euo pipefail

stage_id=""; stamp=""; log=""
while (($#)); do
    case "$1" in
        --id) stage_id="$2"; shift 2 ;;
        --stamp) stamp="$2"; shift 2 ;;
        --log) log="$2"; shift 2 ;;
        --) shift; break ;;
        *) echo "run_stage.sh: unknown argument $1" >&2; exit 2 ;;
    esac
done
[[ -n "$stage_id" && -n "$stamp" && -n "$log" && $# -gt 0 ]] || {
    echo "usage: run_stage.sh --id ID --stamp FILE --log FILE -- command..." >&2
    exit 2
}

mkdir -p "$(dirname "$stamp")" "$(dirname "$log")"
rm -f "$stamp"
started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
    echo "stage=$stage_id"
    echo "started_utc=$started"
    printf 'command='; printf '%q ' "$@"; echo
} | tee "$log"

set +e
"$@" 2>&1 | tee -a "$log"
rc=${PIPESTATUS[0]}
set -e
finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if ((rc != 0)); then
    echo "finished_utc=$finished" | tee -a "$log"
    echo "result=FAIL exit_code=$rc" | tee -a "$log"
    echo "FAILED: $stage_id (see $log)" >&2
    exit "$rc"
fi
{
    echo "stage=$stage_id"
    echo "started_utc=$started"
    echo "finished_utc=$finished"
    echo "result=PASS"
} > "$stamp"
echo "result=PASS" | tee -a "$log"
echo "DONE: $stage_id"

