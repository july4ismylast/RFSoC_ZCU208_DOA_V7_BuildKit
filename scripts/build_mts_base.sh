#!/usr/bin/env bash
# Stage V03, as one command: produce the MTS base project that BASE_XPR points at.
#
#   BASE_XPR = build/mts_base_src_2023p2/boards/ZCU208/build_mts/mts/mts.xpr
#
# No stepNN_ target creates that file; step00_preflight refuses to pass and step07
# onwards cannot open a project until it exists.  This wrapper does the three steps
# that do create it, keeps the Vivado transcript in build/logs/mts_base.log so it can
# be published, and never destroys a base that is already built:
#
#   1. copy the pinned upstream tree and apply the two recorded adaptations
#      (scripts/prepare_mts_2023p2_patch.sh -- it rm -rf's the destination, hence
#       the guard below)
#   2. vivado -mode batch -source mts.tcl in boards/ZCU208/build_mts
#   3. verify mts/mts.xpr exists
#
# Usage:
#   make mts-base                 # build if absent, otherwise report and exit 0
#   make mts-base MTS_BASE_FORCE=1  # wipe and rebuild from the pinned tree
#
# Long: the upstream mts.tcl creates the project and runs it; expect tens of minutes
# to a few hours.  Run it under tmux.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="${BUILD:-$root/build}"
upstream="${UPSTREAM:-$root/upstream}"
dst="$build/mts_base_src_2023p2"
bm="$dst/boards/ZCU208/build_mts"
xpr="$bm/mts/mts.xpr"
log_dir="$build/logs"
log="$log_dir/mts_base.log"
force="${MTS_BASE_FORCE:-0}"

mkdir -p "$log_dir"

if [[ -f "$xpr" && "$force" != "1" ]]; then
    echo "PASS mts base already built: $xpr"
    echo "     $(du -h "$xpr" 2>/dev/null | cut -f1)  mts.xpr"
    echo "     MTS_BASE_FORCE=1 rebuilds it (that removes $dst first)."
    exit 0
fi

src="$upstream/RFSoC-MTS"
if [[ ! -d "$src/.git" ]]; then
    echo "ERROR: $src is not a git checkout." >&2
    echo "Run first: make rebuild STEP=step01_fetch_references FETCH_SET=RFSoC-MTS" >&2
    exit 3
fi

# prepare_mts_2023p2_patch.sh removes $dst, which would take an earlier manual run's
# only transcript with it.  Keep it before anything is deleted.
if [[ -s "$bm/vivado.log" && ! -f "$xpr" ]]; then
    kept="$log_dir/mts_previous_run.log"
    cp -- "$bm/vivado.log" "$kept"
    echo "Kept the previous manual run's transcript as $kept"
fi
if [[ "$force" == "1" && -d "$dst" ]]; then
    echo "MTS_BASE_FORCE=1: removing $dst"
fi
# prepare_mts_2023p2_patch.sh removes and re-copies $dst itself, and refuses a
# checkout whose SHA is not the pinned one.  Both are what we want here.
"$root/scripts/prepare_mts_2023p2_patch.sh"

if [[ ! -f "$bm/mts.tcl" ]]; then
    echo "ERROR: $bm/mts.tcl missing after preparing the tree." >&2
    exit 3
fi

echo
echo "Running the MTS base in Vivado; transcript: $log"
echo "(tens of minutes to a few hours -- run this under tmux)"
echo
set +e
( cd "$bm" && "${VIVADO:-vivado}" -mode batch -source mts.tcl ) 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e

if [[ ! -f "$xpr" ]]; then
    echo >&2
    echo "FAIL Vivado exited $status and produced no $xpr" >&2
    if [[ -s "$log" ]]; then
        echo "First errors in the transcript:" >&2
        grep -n -m 10 -E '^(ERROR|CRITICAL WARNING)' "$log" >&2 || echo "  (none -- the script exited early; see $log)" >&2
    fi
    # Vivado writes its own log in the working directory; an earlier run that was
    # not captured by this wrapper leaves its only transcript there.
    for candidate in "$bm/vivado.log" "$bm/mts/vivado.log"; do
        if [[ -s "$candidate" ]]; then
            echo "Transcribed run found: $candidate" >&2
            grep -n -m 10 -E '^(ERROR|CRITICAL WARNING)' "$candidate" >&2 || echo "  (no ERROR lines in it)" >&2
            break
        fi
    done
    exit 4
fi

echo
echo "PASS mts base: $xpr"
echo "Next:"
echo "  make step00_preflight     # this check was the one failing"
echo "  make pipeline"
