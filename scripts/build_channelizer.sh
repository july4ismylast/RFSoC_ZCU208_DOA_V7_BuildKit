#!/usr/bin/env bash
set -euo pipefail
flow="${1:-${CHANNELIZER_FLOW:-matlab_hdl}}"
case "$flow" in
    matlab_hdl) exec make --no-print-directory -C ip/matlab/channelizer_hdl all ;;
    model_composer) exec make --no-print-directory -C ip/model_composer/channelizer all ;;
    opfb)
        [[ -d "${UPSTREAM}/RFSoC_OPFB" ]] || {
            echo "ERROR: ${UPSTREAM}/RFSoC_OPFB is missing; run make step01_fetch_references FETCH_SET=opfb" >&2
            exit 3
        }
        exec make --no-print-directory -C ip/upstream_opfb all
        ;;
    external)
        [[ -n "${EXTERNAL_CHANNELIZER_IP:-}" && -f "${EXTERNAL_CHANNELIZER_IP}/component.xml" ]] || {
            echo "ERROR: external flow needs EXTERNAL_CHANNELIZER_IP=<directory containing component.xml>" >&2
            exit 3
        }
        echo "Using external channelizer IP: $EXTERNAL_CHANNELIZER_IP"
        ;;
    *) echo "ERROR: CHANNELIZER_FLOW must be matlab_hdl, model_composer, opfb, or external" >&2; exit 2 ;;
esac

