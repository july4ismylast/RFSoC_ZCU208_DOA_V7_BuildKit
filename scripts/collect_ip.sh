#!/usr/bin/env bash
# step06: verify that every packaged IP in $IP_REPO is present AND carries
# exactly the VLNV (vendor:library:name:version) pinned by config.mk +
# config/ip_versions.tcl.  Presence of component.xml alone is not enough --
# a stale core built with another version must fail here, not at step09.
set -euo pipefail
mkdir -p "$IP_REPO"

vendor="${CUSTOM_IP_VENDOR:-openai}"
library="${CUSTOM_IP_LIBRARY:-doa}"

# Print "vendor<TAB>library<TAB>name<TAB>version" from a component.xml.
read_vlnv() {
    python3 - "$1" <<'PYEOF'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
def local(tag):
    return tag.rsplit('}', 1)[-1].rsplit(':', 1)[-1]
vals = {}
for el in root.iter():
    name = local(el.tag)
    if name in ("vendor", "library", "name", "version") and name not in vals:
        if el.text and el.text.strip():
            vals[name] = el.text.strip()
missing = [k for k in ("vendor", "library", "name", "version") if k not in vals]
if missing:
    sys.exit(f"component.xml missing {missing}: {sys.argv[1]}")
print("\t".join(vals[k] for k in ("vendor", "library", "name", "version")))
PYEOF
}

# Required entries are "directory|expected_VLNV" ("-" = record only: the VLNV
# is defined by an external model/tool and must be pinned before production).
required=(
    "$IP_REPO/doa_covariance_4ch_v4|$vendor:$library:doa_covariance_4ch_v4:${IPVER_COVARIANCE:-7.1}"
    "$IP_REPO/spectrum_power4|$vendor:$library:spectrum_power4:${IPVER_SPECTRUM:-2.0}"
    "$IP_REPO/candidate_peak4|$vendor:$library:candidate_peak4:${IPVER_CANDIDATE:-1.0}"
    "$IP_REPO/beam_weight_4ch|$vendor:$library:beam_weight_4ch:${IPVER_BEAM:-2.1}"
    "$IP_REPO/rfdc_repack4|$vendor:$library:rfdc_repack4:${IPVER_RFDC_REPACK4:-1.0}"
)
case "${CHANNELIZER_FLOW:-matlab_hdl}" in
    matlab_hdl) required+=("$IP_REPO/matlab_channelizer|$vendor:$library:matlab_channelizer:${IPVER_CHANNELIZER:-7.0}") ;;
    model_composer) required+=("$IP_REPO/model_composer_channelizer|-") ;;
    external) required+=("${EXTERNAL_CHANNELIZER_IP:-}|-") ;;
    opfb)
        # Exact MazinLab IP set instantiated by the pinned RFSoC_OPFB
        # bd/opfb_streaming.tcl.  "Any component.xml exists" is not enough:
        # every directory below must carry the VLNV pinned in config.mk.
        required+=(
            "$IP_REPO/adc_to_opfb|${OPFB_VLNV_ADC_TO_OPFB:-mazinlab:mkidgen3:adc_to_opfb:1.32}"
            "$IP_REPO/opfb_fir_cfg|${OPFB_VLNV_OPFB_FIR_CFG:-mazinlab:mkidgen3:opfb_fir_cfg:1.31}"
            "$IP_REPO/fir_to_fft|${OPFB_VLNV_FIR_TO_FFT:-mazinlab:mkidgen3:fir_to_fft:1.31}"
            "$IP_REPO/ssrfft_16x4096_axis|${OPFB_VLNV_SSRFFT:-MazinLab:mkidgen3:ssrfft_16x4096_axis:1.0}"
            "$IP_REPO/pkg_fft_output|${OPFB_VLNV_PKG_FFT_OUTPUT:-mazinlab:mkidgen3:pkg_fft_output:1.31}"
            "$IP_REPO/capture_upsizer|${OPFB_VLNV_CAPTURE_UPSIZER:-mazinlab:mkidgen3:capture_upsizer:0.5}"
            "$IP_REPO/filter_iq|${OPFB_VLNV_FILTER_IQ:-mazinlab:mkidgen3:filter_iq:0.3}"
            "$IP_REPO/filter_phase|${OPFB_VLNV_FILTER_PHASE:-mazinlab:mkidgen3:filter_phase:0.5}"
            "$IP_REPO/pair_iq|${OPFB_VLNV_PAIR_IQ:-mazinlab:mkidgen3:pair_iq:0.4}"
            "$IP_REPO/bin_to_res|${OPFB_VLNV_BIN_TO_RES:-mazinlab:mkidgen3:bin_to_res:1.33}"
        )
        ;;
esac

manifest="$IP_REPO/ip_manifest.tsv"
printf 'name\tvendor\tlibrary\tversion\texpected_vlnv\tcomponent_xml\n' > "$manifest"
for entry in "${required[@]}"; do
    directory="${entry%%|*}"
    expected="${entry##*|}"
    [[ -n "$directory" && -f "$directory/component.xml" ]] || {
        echo "ERROR: packaged IP missing: $directory/component.xml" >&2
        echo "Run the corresponding HLS/HDL stage before step06_collect_ip." >&2
        exit 4
    }
    IFS=$'\t' read -r got_vendor got_library got_name got_version < <(read_vlnv "$directory/component.xml")
    got_vlnv="$got_vendor:$got_library:$got_name:$got_version"
    if [[ "$expected" != "-" && "$got_vlnv" != "$expected" ]]; then
        echo "ERROR: IP version mismatch in $directory" >&2
        echo "  expected (config.mk / config/ip_versions.tcl): $expected" >&2
        echo "  packaged component.xml:                        $got_vlnv" >&2
        echo "Rebuild that IP (make rebuild STEP=<its stage>) or fix the IPVER_* variable." >&2
        exit 4
    fi
    if [[ "$expected" == "-" ]]; then
        echo "WARN: $got_vlnv recorded without a pinned expectation (external/model-defined IP). Pin it in config/ip_versions.tcl before production use."
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$got_name" "$got_vendor" "$got_library" "$got_version" "$expected" "$directory/component.xml" >> "$manifest"
    echo "PASS $got_vlnv"
done
echo "Validated IP repository (versions pinned): $manifest"
