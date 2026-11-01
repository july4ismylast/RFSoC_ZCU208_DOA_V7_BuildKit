#!/usr/bin/env bash
set -euo pipefail
build="$1"; shift
printf '%-28s %-10s %s\n' STAGE STATUS FINISHED_UTC
for stage_id in "$@"; do
    stamp="$build/.stamps/$stage_id.done"
    log="$build/logs/$stage_id.log"
    if [[ -f "$stamp" ]]; then
        finished="$(sed -n 's/^finished_utc=//p' "$stamp" | tail -n 1)"
        printf '%-28s %-10s %s\n' "$stage_id" PASS "$finished"
    elif [[ -f "$log" ]]; then
        printf '%-28s %-10s %s\n' "$stage_id" FAILED/OLD "see $log"
    else
        printf '%-28s %-10s %s\n' "$stage_id" NOT-RUN -
    fi
done

