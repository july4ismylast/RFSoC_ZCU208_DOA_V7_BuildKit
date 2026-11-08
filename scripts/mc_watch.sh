#!/usr/bin/env bash
# Is the Model Composer build alive, and what is it doing?
#
# A ten minute "generation in progress" can be a real synthesis or a deadlock, and
# from inside the GUI the two look the same.  This answers it from another
# terminal, without MATLAB:
#
#   make mc-bisect-watch              (watches build/mc_bisect)
#   scripts/mc_watch.sh <folder>      (watches any work folder)
#
# A live build shows a Vivado process with an elapsed time AND a file that keeps
# being touched.  A stall shows one without the other.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
work="${1:-build/mc_bisect}"

echo "== vivado processes"
alive="$(pgrep -fa 'vivado' 2>/dev/null | grep -v 'mc_watch' | grep -v 'pgrep' || true)"
if [ -n "$alive" ]; then
    printf '%s\n' "$alive" | cut -c1-150 | head -6 | sed 's/^/  /'
else
    echo "  none: nothing is being synthesised right now"
fi

echo
echo "== newest files under $work"
if [ -d "$work" ]; then
    find "$work" -type f -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null \
        | sort -r | head -8 | sed 's/^/  /'
else
    echo "  $work does not exist"
fi

echo
echo "== newest log"
newest="$(find "$work" -name '*.log' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
if [ -z "$newest" ]; then
    echo "  no .log under $work yet"
    exit 0
fi
age=$(( $(date +%s) - $(stat -c %Y "$newest") ))
echo "  $newest (last written ${age}s ago)"
if [ "$age" -gt 300 ]; then
    echo "  NOTE: nothing written for more than five minutes"
fi
tail -20 "$newest" | sed 's/^/  | /'

echo
echo "== generated components"
found=0
repo_ip="${IP_REPO:-$root/build/ip_repo}"
for component in "$repo_ip"/ssr_bisect_step*/component.xml "$work"/*_ip/component.xml; do
    [ -f "$component" ] || continue
    found=1
    echo "  $component"
done
if [ "$found" = 0 ]; then
    echo "  none yet"
fi
