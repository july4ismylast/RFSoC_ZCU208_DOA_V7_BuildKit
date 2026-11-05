#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
for script in scripts/*.sh common/scripts/*.sh; do bash -n "$script"; done
for stage_id in $(make --no-print-directory list); do make -n "$stage_id" >/dev/null; done
for required in \
    docs/diagrams/zcu208-overall.jpg \
    matlab_v7/estimate_doa_from_covariance_v7.m \
    ip/custom/doa_covariance_4ch_v4/tb/doa_covariance_4ch_v4_tb.cpp \
    ip/custom/spectrum_power4/tb/spectrum_power4_tb.cpp \
    ip/custom/candidate_peak4/tb/candidate_peak4_tb.cpp \
    ip/custom/beam_weight_4ch/tb/beam_weight_4ch_tb.cpp \
    ip/custom/rfdc_repack4/tb/rfdc_repack4_tb.cpp; do
    [[ -s "$required" ]] || { echo "Missing required file: $required" >&2; exit 2; }
done
if command -v tclsh >/dev/null 2>&1; then
    while IFS= read -r file; do
        FILE="$file" tclsh <<'EOF'
set stream [open $::env(FILE) r]
set text [read $stream]
close $stream
if {![info complete $text]} {error "Incomplete Tcl syntax in $::env(FILE)"}
EOF
    done < <(find common/vivado config ip/matlab/channelizer_hdl -type f \( -name '*.tcl' -o -name '*.xdc' \) | sort)
fi
echo "PASS: shell syntax, Make dry-runs, required artifacts, and Tcl completeness"
