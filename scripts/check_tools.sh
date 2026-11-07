#!/usr/bin/env bash
# What is installed, where, and which gate it unlocks.
#
# The repository's gates G2-G8 need vendor tools that are not in the authoring
# container. This script prints every fact about the *current* machine that the
# gates need, so one paste answers "where is it installed" for all of them.
#
# Run:  make tools    (or: bash scripts/check_tools.sh)
#
# Nothing here writes outside build/ and nothing needs a licence to start; the
# MATLAB probe is skipped unless --matlab is passed, because starting MATLAB
# takes a licence checkout and about a minute.

set -u

MATLAB_PROBE=0
for argument in "$@"; do
  case "${argument}" in
    --matlab) MATLAB_PROBE=1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}" || exit 1

say() { printf '\n=== %s\n' "$1"; }
row() { printf '  %-22s %s\n' "$1" "$2"; }
have() { command -v "$1" >/dev/null 2>&1; }
version_of() { "$1" "$2" 2>&1 | head -3 | tr '\n' ' '; }

say "host"
row "uname" "$(uname -srm)"
row "cores" "$(nproc 2>/dev/null || echo '?')"
row "memory" "$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo '?')"
row "disk (root)" "$(df -h / | awk 'NR==2{print $4" free"}')"

say "G2 G3 G4  Vitis HLS and Vivado 2023.2"
for tool in vivado vivado_lab vitis_hls vitis; do
  if have "${tool}"; then
    row "${tool}" "$(command -v "${tool}")  $(version_of "${tool}" -version)"
  else
    row "${tool}" "not on PATH"
  fi
done
row "XILINX_VIVADO" "${XILINX_VIVADO:-unset}"
row "XILINX_HLS" "${XILINX_HLS:-unset}"
row "VIVADO (config.mk)" "$(grep -E '^VIVADO *\?=' Makefile config.mk 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' ')"
row "VITIS_HLS (config.mk)" "$(grep -E '^VITIS_HLS *\?=' Makefile config.mk 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' ')"
for path in /tools/Xilinx /opt/Xilinx /usr/local/Xilinx "${HOME}/Xilinx"; do
  [ -d "${path}" ] && row "found" "${path}"
done

say "G4  the licensed base project"
base="$(grep -E '^BASE_XPR' config.mk Makefile 2>/dev/null | head -1 | cut -d= -f2- \
        | sed "s|\$(BUILD)|${ROOT}/build|" | tr -d ' ')"
row "BASE_XPR" "${base:-unset}"
if [ -n "${base}" ] && [ -e "${base}" ]; then
  row "  exists" "yes ($(stat -c %y "${base}" 2>/dev/null | cut -d' ' -f1))"
else
  row "  exists" "no -- G4 cannot start without it"
fi

say "G8b  MATLAB, Embedded Coder and the R5 toolchain"
if have matlab; then
  row "matlab" "$(command -v matlab)"
else
  row "matlab" "not on PATH"
fi
row "MATLAB_ROOT" "${MATLAB_ROOT:-unset}"
row "V7_MATLAB_ROOT" "${V7_MATLAB_ROOT:-unset}"
for compiler in armr5-none-eabi-gcc arm-none-eabi-gcc aarch64-none-elf-gcc; do
  if have "${compiler}"; then
    row "${compiler}" "$(command -v "${compiler}")  $("${compiler}" -dumpversion 2>/dev/null)"
  else
    row "${compiler}" "not on PATH"
  fi
done
if [ "${MATLAB_PROBE}" -eq 1 ] && have matlab; then
  row "matlab -batch ver" "checking (about 60 s, takes a licence)"
  matlab -batch "v=ver; fprintf('%s %s\n', v.Name, v.Version)" 2>&1 \
    | grep -Ei 'simulink|embedded|hdl|fixed|signal|matlab ' | head -12
fi

say "G5 G6 G7b  the board"
row "serial devices" "$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | tr '\n' ' ' || echo none)"
row "usb (Xilinx)" "$(lsusb 2>/dev/null | grep -ci xilinx 2>/dev/null || echo '0')"
row "ethernet peers" "$(ip -brief addr 2>/dev/null | awk 'NR>1{print $2" "$3}' | tr '\n' ';' || echo '?')"

say "host toolchain for the studies (G0, G1a/b, G8a)"
for tool in python3 gcc g++ make; do
  have "${tool}" && row "${tool}" "$(command -v "${tool}")  $("${tool}" --version 2>&1 | head -1)"
done
python3 - <<'PY' 2>/dev/null || echo "  numpy: not importable"
import numpy, sys
print("  %-22s %s" % ("numpy", numpy.__version__))
try:
    import matplotlib
    print("  %-22s %s" % ("matplotlib", matplotlib.__version__))
except Exception:
    print("  %-22s %s" % ("matplotlib", "missing (needed by make diagram)"))
PY
have mh_lint && row "mh_lint" "$(command -v mh_lint)"

say "what each answer unlocks"
cat <<'TEXT'
  Vitis HLS 2023.2 path      -> G2 (make step05_hls_phase_interf), then G3, G4
  Vivado 2023.2 path         -> G3 (gate3-ooc), G4 (steps 07-13)
  BASE_XPR (MTS base)        -> G4 only; without it steps 08-11 cannot run
  MATLAB + Embedded Coder    -> G8b (matlab_v7/build_amc_r5.m)
  armr5-none-eabi-gcc        -> G8b link; also the ABI check for the library
  board (serial + ethernet)  -> Gsh5 (loopback), G6 (chamber), G7b, G8c
  no vendor tools at all     -> G0, G1a/b/c, G7a, G8a still work: they are the
                                green half of this repository
TEXT
