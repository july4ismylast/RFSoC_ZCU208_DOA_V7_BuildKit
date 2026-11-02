#!/usr/bin/env bash
# step00 preflight: tools, part/board, and the V00 version lock.
# The lock is hard now: EXPECTED_VIVADO_VERSION must be set (default 2023.2 in
# config.mk) and must match the installed Vivado *and* Vitis HLS.  At the end
# it runs common/vivado/00_check_ip_catalog.tcl so the pinned VLNV table in
# config/ip_versions.tcl is proven against the installed 2023.2 catalog
# (skip only with SKIP_IP_CATALOG_CHECK=1 for tool-presence smoke tests).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
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
check_tool python3
check_tool "${VITIS_HLS:-vitis_hls}"
check_tool "${VIVADO:-vivado}"
check_tool "${MATLAB:-matlab}"

[[ "${PART:-}" == "xczu48dr-fsvg1517-2-e" ]] || {
    echo "FAIL PART=${PART:-unset}; ZCU208 must use xczu48dr-fsvg1517-2-e"
    failures=$((failures+1))
}
if [[ "${BOARD_PART:-}" == "xilinx.com:zcu208:part0:2.0" ]]; then
    echo "PASS BOARD_PART=${BOARD_PART}"
else
    echo "FAIL BOARD_PART=${BOARD_PART:-unset}; pinned ZCU208 board part is xilinx.com:zcu208:part0:2.0 (config.mk / config/ip_versions.tcl)"
    failures=$((failures+1))
fi
case "${BASE_KIND:-mts}" in
    mts) echo "PASS BASE_KIND=mts (Xilinx RFSoC-MTS ZCU208 standard MTS base)" ;;
    *) echo "FAIL BASE_KIND=${BASE_KIND:-unset}; only 'mts' is certified for the Vivado-first flow (see VIVADO stage plan V03)"
       failures=$((failures+1)) ;;
esac
if [[ -n "${BASE_XPR:-}" ]]; then
    [[ -f "$BASE_XPR" ]] || { echo "FAIL BASE_XPR does not exist: $BASE_XPR"; failures=$((failures+1)); }
else
    echo "WARN BASE_XPR is unset; steps 07-13 will stop until a verified ZCU208 RFDC/MTS project is supplied"
    warnings=$((warnings+1))
fi

if [[ -z "${EXPECTED_VIVADO_VERSION:-}" ]]; then
    echo "FAIL EXPECTED_VIVADO_VERSION is empty; the V00 lock requires a pinned version (config.mk default: 2023.2)"
    failures=$((failures+1))
fi
if command -v "${VIVADO:-vivado}" >/dev/null 2>&1; then
    actual="$(${VIVADO:-vivado} -version 2>/dev/null | sed -n '1s/.*v\([0-9][0-9.]*\).*/\1/p')"
    echo "INFO Vivado version=${actual:-unknown} (lock: ${EXPECTED_VIVADO_VERSION:-unset})"
    if [[ -n "${EXPECTED_VIVADO_VERSION:-}" && "$actual" != "$EXPECTED_VIVADO_VERSION" ]]; then
        echo "FAIL EXPECTED_VIVADO_VERSION=$EXPECTED_VIVADO_VERSION but detected $actual"
        failures=$((failures+1))
    fi
fi
if command -v "${VITIS_HLS:-vitis_hls}" >/dev/null 2>&1; then
    hls_actual="$(${VITIS_HLS:-vitis_hls} -version 2>/dev/null | grep -oE '20[0-9]{2}\.[0-9]+' | head -n 1 || true)"
    if [[ -n "$hls_actual" ]]; then
        echo "INFO Vitis HLS version=$hls_actual (lock: ${EXPECTED_VIVADO_VERSION:-unset})"
        if [[ -n "${EXPECTED_VIVADO_VERSION:-}" && "$hls_actual" != "$EXPECTED_VIVADO_VERSION" ]]; then
            echo "FAIL Vitis HLS $hls_actual does not match Vivado lock $EXPECTED_VIVADO_VERSION; HLS IP built by another release must not enter this BD"
            failures=$((failures+1))
        fi
    else
        echo "WARN could not parse Vitis HLS version from -version output; verify it is ${EXPECTED_VIVADO_VERSION:-the locked release} manually"
        warnings=$((warnings+1))
    fi
fi
echo "INFO channelizer flow=${CHANNELIZER_FLOW:-matlab_hdl}"
echo "INFO custom IP VLNVs=${CUSTOM_IP_VENDOR:-openai}:${CUSTOM_IP_LIBRARY:-doa}:doa_covariance_4ch_v4:${IPVER_COVARIANCE:-7.1}, spectrum_power4:${IPVER_SPECTRUM:-2.0}, candidate_peak4:${IPVER_CANDIDATE:-1.0}, beam_weight_4ch:${IPVER_BEAM:-2.1}, rfdc_repack4:${IPVER_RFDC_REPACK4:-1.0}, matlab_channelizer:${IPVER_CHANNELIZER:-7.0}"
echo "INFO RF target=${TARGET_RF_LOW_HZ:-2000000000}-${TARGET_RF_HIGH_HZ:-4000000000} Hz on ${ADC_CHANNEL_COUNT:-4} ADC channels"
echo "INFO PL contract=${ADC_STREAM_BITS:-512} bits at ${PL_CLOCK_PERIOD_NS:-7.8125} ns"
echo "SUMMARY failures=$failures warnings=$warnings"
((failures == 0)) || exit 1

if [[ "${SKIP_IP_CATALOG_CHECK:-0}" == "1" ]]; then
    echo "WARN SKIP_IP_CATALOG_CHECK=1: pinned VLNV table was NOT proven against the installed Vivado catalog"
    exit 0
fi
echo "Proving pinned IP catalog in Vivado (common/vivado/00_check_ip_catalog.tcl)..."
"${VIVADO:-vivado}" -mode batch -nojournal -nolog -source "$root/common/vivado/00_check_ip_catalog.tcl"
