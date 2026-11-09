#!/usr/bin/env bash
# The bring-up, in the only order that works, with the gate each step closes.
#
# Nothing in this script runs anything by default: it prints the commands. The
# ones marked [done] are closed by a script in this repository; the rest need
# your tools, your licence, or the board.
#
#   bash step7_board_bringup/checklist.sh          # print the list
#   bash step7_board_bringup/checklist.sh --run 2  # run step 2 (and only it)
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}" || exit 1

RUN=""
if [ "${1:-}" = "--run" ]; then
  RUN="${2:-}"
fi

steps=(
"done|G0,G1a,G1b,G1c,G7a,G8a|the host half|make steps"
"|G-tools|what is installed, and where|make tools"
"|G2|the eight HLS kernels, csim + csynth at 4.000 ns|make hls-all"
"|G2|the reports that prove it|make -C ip/custom/phase_interf_4ch collect-reports"
"|G3|out-of-context synthesis of phase_interf_4ch|make -C ip/custom/phase_interf_4ch gate3-ooc"
"|G4|the Vivado build -- needs BASE_XPR|make step07_vivado_base BASE_XPR=<path>/mts.xpr"
"|G4|synthesis, implementation, bitstream, XSA|make step10_synth step11_impl step12_bitstream step13_export_xsa"
"|G8b|MATLAB -> Embedded Coder -> C for the AMC|matlab -batch \"cd matlab_v7; verify_amc_vectors\"; matlab -batch \"cd matlab_v7; build_amc_r5\""
"|G5|boot, then the DAC->ADC loopback capture|(on the board) dd if=/dev/xdma0_c2h_0 of=/tmp/loop.bin bs=65568 count=16"
"|G6|the chamber sweep, one angle at a time|(script to write: step0_antenna/testbench/compare_with_capture.py --captures DIR)"
"|G7b|the estimator on board captures|(flag to add) python3 step3_r5_doa/testbench/run_testbench.py --from-capture DIR"
"|G8c|cycles per burst on the R5|(on the board) time 100 bursts through the AMC"
)

printf '\nZCU208 DOA V7 -- bring-up checklist\n'
printf '===================================\n'
index=0
for row in "${steps[@]}"; do
  index=$((index + 1))
  state="$(printf '%s' "${row}" | cut -d'|' -f1)"
  gate="$(printf '%s' "${row}" | cut -d'|' -f2)"
  what="$(printf '%s' "${row}" | cut -d'|' -f3)"
  command="$(printf '%s' "${row}" | cut -d'|' -f4- | sed 's/|/ /g')"
  mark="   "
  [ "${state}" = "done" ] && mark="[x]"
  printf '%s %2d  %-14s %-46s\n' "${mark}" "${index}" "${gate}" "${what}"
  printf '          $ %s\n' "${command}"
  if [ -n "${RUN}" ] && [ "${RUN}" = "${index}" ]; then
    printf '          ... running\n'
    bash -c "${command}"
  fi
done
printf '\nThe unchecked lines are the open gates. A gate closes when its log exists\n'
printf 'in docs/evidence/, not when the command was typed.\n\n'
