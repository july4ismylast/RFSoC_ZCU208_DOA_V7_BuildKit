#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
flow="${1:-${CHANNELIZER_FLOW:-matlab_hdl}}"
case "$flow" in
    matlab_hdl) exec make --no-print-directory -C ip/matlab/channelizer_hdl all ;;
    model_composer) exec make --no-print-directory -C ip/model_composer/channelizer all ;;
    opfb)
        # ip/upstream_opfb/Makefile fetches the pinned OPFB set once and then
        # builds only the IP adapters used by the pinned RFSoC_OPFB BD.
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
