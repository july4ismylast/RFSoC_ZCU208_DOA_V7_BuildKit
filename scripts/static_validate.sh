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
    ip/custom/rfdc_repack4/tb/rfdc_repack4_tb.cpp \
    ip/custom/doa_subband_bridge_4ch/rtl/doa_subband_bridge_4ch.v \
    ip/custom/doa_subband_bridge_4ch/tb/tb_doa_subband_bridge_4ch.sv \
    ip/custom/doa_subband_bridge_4ch/package_ip.tcl \
    ip/custom/doa_subband_bridge_4ch/verify_golden_model.py \
    ip/matlab/channelizer_hdl/channelizer_axis_wrapper.sv; do
    [[ -s "$required" ]] || { echo "Missing required file: $required" >&2; exit 2; }
done

python3 ip/custom/doa_subband_bridge_4ch/verify_golden_model.py

# Static Tcl delimiter/quote completeness check (always runs via python3, and
# additionally uses tclsh info complete when tclsh is installed).
python3 - <<'PYEOF'
import pathlib, sys

roots = [
    pathlib.Path("common/vivado"),
    pathlib.Path("config"),
    pathlib.Path("ip/matlab/channelizer_hdl"),
    pathlib.Path("ip/custom"),
]
files = sorted({
    p for r in roots if r.exists()
    for p in r.rglob("*")
    if p.is_file() and p.suffix in (".tcl", ".xdc") and "hdl_prj" not in p.parts
})

for path in files:
    text = path.read_text(encoding="utf-8")
    stack = []
    in_quote = False
    in_comment = False
    at_cmd_start = True
    escaped = False
    line_no = 1
    for ch in text:
        if ch == "\n":
            line_no += 1
            if not escaped:
                in_comment = False
                if not in_quote and not stack:
                    at_cmd_start = True
            escaped = False
            continue
        if escaped:
            escaped = False
            continue
        if ch == "\\":
            escaped = True
            continue
        if in_comment:
            continue
        if in_quote:
            if ch == '"':
                in_quote = False
            elif ch == "[" and (not stack or stack[-1][0] != "{"):
                stack.append(("[", line_no))
            elif ch == "]" and stack and stack[-1][0] == "[":
                stack.pop()
            continue
        if stack and stack[-1][0] == "{":
            if ch == "{":
                stack.append(("{", line_no))
            elif ch == "}":
                stack.pop()
            continue
        if at_cmd_start:
            if ch in (" ", "\t", "\r"):
                continue
            if ch == "#":
                in_comment = True
                at_cmd_start = False
                continue
            at_cmd_start = False
        if ch == ";":
            if not stack:
                at_cmd_start = True
            continue
        if ch == '"':
            in_quote = True
        elif ch == "{":
            stack.append(("{", line_no))
        elif ch == "}":
            sys.exit(f"Unmatched '}}' in {path}:{line_no}")
        elif ch == "[":
            stack.append(("[", line_no))
        elif ch == "]":
            if not stack or stack[-1][0] != "[":
                sys.exit(f"Unmatched ']' in {path}:{line_no}")
            stack.pop()
    if in_quote:
        sys.exit(f"Unterminated '\"' in {path}")
    if stack:
        tok, ln = stack[-1]
        sys.exit(f"Unclosed '{tok}' opened at {path}:{ln}")
print(f"PASS: Tcl/XDC delimiter check across {len(files)} files")
PYEOF

if command -v tclsh >/dev/null 2>&1; then
    while IFS= read -r file; do
        FILE="$file" tclsh <<'EOF'
set stream [open $::env(FILE) r]
set text [read $stream]
close $stream
if {![info complete $text]} {error "Incomplete Tcl syntax in $::env(FILE)"}
EOF
    done < <(find common/vivado config ip/matlab/channelizer_hdl ip/custom -type f \( -name '*.tcl' -o -name '*.xdc' \) | sort)
fi
echo "PASS: shell syntax, Make dry-runs, required artifacts, and Tcl completeness"
