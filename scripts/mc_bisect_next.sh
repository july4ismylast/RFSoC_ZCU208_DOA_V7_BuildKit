#!/usr/bin/env bash
# What is proven, and what to run next.
#
# Each generation on this host costs a couple of minutes and can be interrupted by
# the SysGen hand-back hang, so the loop is: cancel, harvest, rerun from the next
# step.  This prints exactly which step that is, from what is on disk.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
repo="${IP_REPO:-build/ip_repo}"
labels=("export target IP Catalog" "retarget device to MC_PART" \
        "name the exported subsystem" "our sample format 16.14" \
        "our latency 4" "our channels: gateway -> delay -> gateway")
last=0
echo "collected artifacts in $repo:"
for step in 1 2 3 4 5 6; do
    component="$repo/ssr_bisect_step$step/component.xml"
    if [ -f "$component" ]; then
        vlnv="$(python3 scripts/check_ip_component.py "$component" --any-ports 2>/dev/null | head -1)"
        name="$(python3 - "$component" <<'PY'
import sys, xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    print("?"); raise SystemExit
for element in root.iter():
    tag = element.tag.rsplit("}", 1)[-1]
    if tag == "name" and element.text and element.text.strip():
        print(element.text.strip()); break
PY
)"
        printf '  step %d  %-34s %s  block=%s\n' "$step" "${labels[$((step-1))]}" "${vlnv#VLNV: }" "$name"
        last=$step
    fi
done
if [ "$last" = 0 ]; then
    echo "  none"
fi

echo
if unstaged="$(python3 scripts/mc_bisect_harvest.py 2>/dev/null)" && printf '%s' "$unstaged" | grep -q 'min  '; then
    echo "uncollected components the engine wrote:"
    printf '%s\n' "$unstaged" | head -6 | sed 's/^/  /'
    echo
fi

if [ "$last" -ge 6 ]; then
    echo "all six steps have artifacts: make mc-adopt-bisect"
    exit 0
fi
next=$((last + 1))
echo "next: make mc-bisect MC_BISECT_FROM=$next"
