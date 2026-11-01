#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$IP_REPO"
required=("$IP_REPO/doa_covariance_4ch_v4" "$IP_REPO/spectrum_power4" "$IP_REPO/candidate_peak4" "$IP_REPO/beam_weight_4ch")
case "${CHANNELIZER_FLOW:-matlab_hdl}" in
    matlab_hdl) required+=("$IP_REPO/matlab_channelizer") ;;
    model_composer) required+=("$IP_REPO/model_composer_channelizer") ;;
    external) required+=("${EXTERNAL_CHANNELIZER_IP:-}") ;;
    opfb)
        if ! find "$IP_REPO" -path '*/component.xml' -print -quit | grep -q .; then
            echo "ERROR: no OPFB component.xml files were collected" >&2; exit 4
        fi
        ;;
esac
manifest="$IP_REPO/ip_manifest.tsv"
printf 'name\tcomponent_xml\n' > "$manifest"
for directory in "${required[@]}"; do
    [[ -n "$directory" && -f "$directory/component.xml" ]] || {
        echo "ERROR: packaged IP missing: $directory/component.xml" >&2
        echo "Run the corresponding HLS/HDL stage before step06_collect_ip." >&2
        exit 4
    }
    printf '%s\t%s\n' "$(basename "$directory")" "$directory/component.xml" >> "$manifest"
done
echo "Validated IP repository: $manifest"
