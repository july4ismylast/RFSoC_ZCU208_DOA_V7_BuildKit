#!/usr/bin/env bash
# What is installed, where, and which gate it unlocks.
#
# The repository's gates G2-G8 need vendor tools that are not in the authoring
# container. This script prints every fact about the *current* machine that the
# gates need, so one paste answers "where is it installed" for all of them.
#
# Run:  make tools            (or: bash scripts/check_tools.sh)
#       make tools MATLAB=1   (also starts MATLAB and checks the toolboxes)
#
# Nothing here writes outside build/ and the MATLAB probe is the only part that
# takes a licence, which is why it is opt-in.

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
row() { printf '  %-26s %s\n' "$1" "$2"; }
have() { command -v "$1" >/dev/null 2>&1; }
version_of() { "$1" "$2" 2>&1 | head -3 | tr '\n' ' '; }

# release of any MATLAB-family install, read from <root>/VersionInfo.xml so it
# costs no licence and no 40-second start-up.
release_of() {
  local exe root
  exe="$1"
  [ -n "${exe}" ] || { printf 'unset'; return; }
  if [ -x "${exe}" ]; then
    root="$(dirname "$(dirname "$(readlink -f "${exe}")")")"
  elif [ -d "${exe}" ]; then
    root="${exe}"
  else
    printf 'not found'; return
  fi
  if [ -r "${root}/VersionInfo.xml" ]; then
    sed -n 's:.*<release>\(.*\)</release>.*:\1:p' "${root}/VersionInfo.xml" | head -1
  else
    printf 'unknown (no VersionInfo.xml in %s)' "${root}"
  fi
}

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
row "XILINX_VITIS" "${XILINX_VITIS:-unset}"
for path in /tools/Xilinx /opt/Xilinx /usr/local/Xilinx "${HOME}/Xilinx"; do
  [ -d "${path}" ] && row "found" "${path}"
done

say "Model Composer  (its own MATLAB: 2022b in this kit)"
row "MODEL_COMPOSER" "${MODEL_COMPOSER:-unset}"
if [ -n "${MODEL_COMPOSER:-}" ] && [ -x "${MODEL_COMPOSER}" ]; then
  row "  exists" "yes, Model Composer $(release_of "${MODEL_COMPOSER}")"
elif [ -n "${MODEL_COMPOSER:-}" ]; then
  row "  exists" "no -- the path in MODEL_COMPOSER is not executable"
else
  row "  exists" "unset -- only step05_channelizer CHANNELIZER_FLOW=model_composer needs it"
fi
row "MODEL_COMPOSER_MODEL" "${MODEL_COMPOSER_MODEL:-unset (path to your .slx)}"
row "MATLAB_2022B" "${MATLAB_2022B:-unset}"
if [ -n "${MATLAB_2022B:-}" ]; then
  row "  release" "$(release_of "${MATLAB_2022B}")"
fi

say "G4  the licensed base project"
base="$(grep -hE '^BASE_XPR *\?=' config.mk 2>/dev/null | head -1 | sed 's/^[^=]*= *//')"
base="${base//\$(BUILD)/${ROOT}/build}"
row "BASE_XPR" "${base:-unset}"
if [ -n "${base}" ] && [ -e "${base}" ]; then
  row "  exists" "yes ($(stat -c %y "${base}" 2>/dev/null | cut -d' ' -f1))"
else
  row "  exists" "no -- G4 cannot start until stage V03 builds it"
fi

say "G8b  MATLAB, Embedded Coder and the R5 toolchain"
if have matlab; then
  row "matlab" "$(command -v matlab)  ($(release_of "$(command -v matlab)"))"
  row "  resolves to" "$(readlink -f "$(command -v matlab)" 2>/dev/null || echo '?')"
else
  row "matlab" "not on PATH"
fi
row "EXPECTED_MATLAB_RELEASE" "$(grep -E '^EXPECTED_MATLAB_RELEASE' config.mk | cut -d= -f2- | tr -d ' ')"
if have matlab; then
  actual="$(release_of "$(command -v matlab)")"
  expected="$(grep -E '^EXPECTED_MATLAB_RELEASE' config.mk | cut -d= -f2- | tr -d ' ')"
  if [ "${actual}" = "${expected}" ]; then
    row "  matches the lock" "yes"
  else
    row "  matches the lock" "NO (matlab is ${actual}, lock is ${expected})"
  fi
fi
row "MATLAB_ROOT" "${MATLAB_ROOT:-unset}"
row "V7_MATLAB_ROOT" "${V7_MATLAB_ROOT:-unset}"
for compiler in armr5-none-eabi-gcc arm-none-eabi-gcc aarch64-none-elf-gcc aarch64-linux-gnu-gcc; do
  if have "${compiler}"; then
    row "${compiler}" "$(command -v "${compiler}")  $("${compiler}" -dumpversion 2>/dev/null)"
  else
    row "${compiler}" "not on PATH"
  fi
done

if [ "${MATLAB_PROBE}" -eq 1 ] && have matlab; then
  say "G8b  the toolboxes (one licence checkout, about 40 s)"
  probe="$(mktemp -t doa-matlab-ver-XXXXXX)"
  if matlab -batch "v=ver; for k=1:numel(v), fprintf('%s | %s\n', v(k).Name, v(k).Version); end" \
      > "${probe}" 2>&1; then
    row "products found" "$(grep -c '|' "${probe}")"
    for product in "MATLAB Coder" "Simulink" "Simulink Coder" "Embedded Coder" \
                   "Fixed-Point Designer" "HDL Coder" "DSP HDL Toolbox" \
                   "Embedded Coder Support Package for ARM Cortex-R Processors"; do
      if grep -qi "^${product} |" "${probe}"; then
        printf '  [ok]   %s\n' "${product}"
      else
        printf '  [MISS] %s\n' "${product}"
      fi
    done
    printf '  all products: '
    sed -n 's/ | .*//p' "${probe}" | paste -sd ', ' -
    printf '\n'
    printf '  note: the ARM Cortex-R support package is only needed for on-target\n'
    printf '        PIL/deployment. G8b uses coder.config("lib") + GenCodeOnly and\n'
    printf '        links with armr5-none-eabi-gcc, so it is not required.\n'
  else
    row "matlab -batch" "FAILED -- see the output above"
  fi
  rm -f "${probe}"
fi

say "G5 G6 G7b  the board"
serial="$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | tr '\n' ' ')"
row "serial devices" "${serial:-none}"
if have lsusb; then
  row "usb (Xilinx)" "$(lsusb 2>/dev/null | grep -ci xilinx || true)"
else
  row "usb (Xilinx)" "lsusb not installed"
fi
row "ethernet" "$(ip -brief addr 2>/dev/null | awk 'NR>1{print $2" "$3}' | tr '\n' ';' || echo '?')"

say "host toolchain for the studies (G0, G1a/b, G8a)"
for tool in python3 gcc g++ make; do
  have "${tool}" && row "${tool}" "$(command -v "${tool}")  $("${tool}" --version 2>&1 | head -1)"
done
python3 - <<'PY' 2>/dev/null || echo "  numpy: not importable"
import numpy, sys
print("  %-26s %s" % ("python", sys.version.split()[0]))
print("  %-26s %s" % ("numpy", numpy.__version__))
try:
    import matplotlib
    print("  %-26s %s" % ("matplotlib", matplotlib.__version__))
except Exception:
    print("  %-26s %s" % ("matplotlib", "missing (needed by make diagram)"))
PY
have mh_lint && row "mh_lint" "$(command -v mh_lint)"

say "what each answer unlocks"
cat <<'TEXT'
  Vitis HLS 2023.2 path      -> G2 (make hls-all), then G3, G4
  Vivado 2023.2 path         -> G3 (gate3-ooc), G4 (steps 07-13)
  BASE_XPR (MTS base)        -> G4 ONLY. Until stage V03 produces it, steps
                                07-13 cannot run; everything before them can.
  MATLAB 2024a + Embedded    -> G8b (matlab_v7/build_amc_r5.m), step14 vectors
  MATLAB 2022b + Model Comp. -> step05_channelizer CHANNELIZER_FLOW=model_composer
  armr5-none-eabi-gcc        -> the R5 link, and the ABI check for the library
  board (serial + ethernet)  -> G5 (loopback), G6 (chamber), G7b, G8c
  no vendor tools at all     -> G0, G1a/b/c, G7a, G8a still work: they are the
                                green half of this repository
TEXT
