#!/usr/bin/env bash
set -euo pipefail
failures=0; warnings=0
check_tool() {
    local name="$1"
    if command -v "$name" >/dev/null 2>&1; then
        printf 'PASS tool %-12s %s\n' "$name" "$(command -v "$name")"
    else
        printf 'FAIL tool %-12s not found on PATH\n' "$name"
        failures=$((failures+1))
    fi
}
check_tool make
check_tool git
check_tool "${VITIS_HLS:-vitis_hls}"
check_tool "${VIVADO:-vivado}"
check_tool "${MATLAB:-matlab}"

[[ "${PART:-}" == "xczu48dr-fsvg1517-2-e" ]] || {
    echo "FAIL PART=${PART:-unset}; ZCU208 must use xczu48dr-fsvg1517-2-e"
    failures=$((failures+1))
}
if [[ -n "${BASE_XPR:-}" ]]; then
    [[ -f "$BASE_XPR" ]] || { echo "FAIL BASE_XPR does not exist: $BASE_XPR"; failures=$((failures+1)); }
else
    echo "WARN BASE_XPR is unset; steps 07-13 will stop until a verified ZCU208 RFDC/MTS project is supplied"
    warnings=$((warnings+1))
fi

if command -v "${VIVADO:-vivado}" >/dev/null 2>&1; then
    actual="$(${VIVADO:-vivado} -version 2>/dev/null | sed -n '1s/.*v\([0-9][0-9.]*\).*/\1/p')"
    echo "INFO Vivado version=${actual:-unknown}"
    if [[ -n "${EXPECTED_VIVADO_VERSION:-}" && "$actual" != "$EXPECTED_VIVADO_VERSION" ]]; then
        echo "FAIL EXPECTED_VIVADO_VERSION=$EXPECTED_VIVADO_VERSION but detected $actual"
        failures=$((failures+1))
    fi
fi
if [[ -z "${EXPECTED_VIVADO_VERSION:-}" ]]; then
    echo "WARN EXPECTED_VIVADO_VERSION is empty; pin it to the BASE_XPR version before production"
    warnings=$((warnings+1))
fi
echo "INFO channelizer flow=${CHANNELIZER_FLOW:-matlab_hdl}"
echo "INFO PL contract=${ADC_STREAM_BITS:-512} bits at ${PL_CLOCK_PERIOD_NS:-7.8125} ns"
echo "SUMMARY failures=$failures warnings=$warnings"
((failures == 0))

