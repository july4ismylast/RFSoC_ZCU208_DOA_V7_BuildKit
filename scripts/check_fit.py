#!/usr/bin/env python3
"""Does the design fit on the ZCU208 (xczu48dr-fsvg1517-2-e), and does it close timing?

Reads the reports the Vivado stages already write -- nothing is run here, so this is
honest about the difference between "not measured yet" and "measured and fine":

  build/output/post_synth_utilization.rpt   written by step10_synth
  build/output/post_route_utilization.rpt   written by step11_impl
  build/output/post_route_timing.rpt        written by step11_impl

Vivado's own report carries the device capacity in its "Available" column, so this
script never hard-codes device totals that could drift from the part in config.mk.

Exit codes: 0 everything measured and comfortable, 1 something does not fit or does not
close timing, 2 nothing measured yet (run the stage first).

Usage: python3 scripts/check_fit.py [--json]
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "output"

# Rows worth quoting, in the order they should be read.
WATCHED = [
    "CLB LUTs",
    "CLB Registers",
    "CARRY8",
    "CLB",
    "Block RAM Tile",
    "RAMB36/FIFO",
    "RAMB18",
    "URAM",
    "DSPs",
    "Bonded IOB",
    "BUFGCE",
]
WARN_PERCENT = 85.0


def parse_utilization(path):
    rows = {}
    if not path.is_file():
        return rows
    for line in path.read_text(errors="replace").splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 6:
            continue
        name, used, _fixed, _prohibited, available, util = cells
        if name in ("Site Type", "") or set(name) <= {"-", " "}:
            continue
        try:
            rows[name] = {
                "used": int(used.replace(",", "")),
                "available": int(available.replace(",", "")),
                "util": float(util.rstrip("%")),
            }
        except ValueError:
            continue
    return rows


def parse_wns(path):
    """Worst negative slack from report_timing_summary's Design Timing Summary."""
    if not path.is_file():
        return None
    lines = path.read_text(errors="replace").splitlines()
    for index, line in enumerate(lines):
        if "WNS(ns)" in line:
            for follow in lines[index + 1:index + 5]:
                numbers = re.findall(r"-?\d+\.\d+", follow)
                if numbers:
                    return float(numbers[0])
    return None


def main():
    as_json = "--json" in sys.argv
    synth = OUT / "post_synth_utilization.rpt"
    route = OUT / "post_route_utilization.rpt"
    timing = OUT / "post_route_timing.rpt"

    source = route if route.is_file() else synth
    rows = parse_utilization(source)
    wns = parse_wns(timing)

    result = {"report": str(source) if rows else None, "wns_ns": wns,
              "resources": {}, "verdict": None, "failures": [], "warnings": []}

    if not rows:
        result["verdict"] = "NOT-MEASURED"
        if as_json:
            print(json.dumps(result, indent=2))
        else:
            print("NOT-MEASURED: no utilization report under build/output")
            print("  a design has not been synthesized yet, so nothing can be said about")
            print("  whether it fits.  Run: make step10_synth   (or make pipeline)")
        return 2

    for name in WATCHED:
        if name not in rows:
            continue
        entry = rows[name]
        result["resources"][name] = entry
        if entry["util"] > 100.0:
            result["failures"].append(f"{name} {entry['util']:.1f}% -- does not fit")
        elif entry["util"] > WARN_PERCENT:
            result["warnings"].append(f"{name} {entry['util']:.1f}% -- tight for place and route")

    if wns is not None and wns < 0:
        result["failures"].append(f"post-route WNS {wns:.3f} ns -- timing does not close")
    elif wns is not None and wns < 0.050:
        result["warnings"].append(f"post-route WNS {wns:.3f} ns -- closes with almost no margin")

    result["verdict"] = "FAIL" if result["failures"] else ("WARN" if result["warnings"] else "PASS")

    if as_json:
        print(json.dumps(result, indent=2))
    else:
        print(f"report: {source.relative_to(ROOT)}")
        if not route.is_file() and synth.is_file():
            print("        (post-synthesis only -- run step11_impl for the placed numbers)")
        print()
        print(f"{'resource':<18}{'used':>10}{'available':>12}{'util %':>9}")
        for name, entry in result["resources"].items():
            print(f"{name:<18}{entry['used']:>10,}{entry['available']:>12,}{entry['util']:>9.2f}")
        print()
        if wns is None:
            print("timing: no post-route timing report yet (run make step11_impl)")
        else:
            print(f"timing: post-route WNS {wns:.3f} ns")
        for failure in result["failures"]:
            print(f"  FAIL {failure}")
        for warning in result["warnings"]:
            print(f"  WARN {warning}")
        print(f"RESULT={result['verdict']}")

    return 1 if result["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
