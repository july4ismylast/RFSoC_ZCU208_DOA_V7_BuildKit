#!/usr/bin/env bash
set -euo pipefail
stage="$1"; build="$2"; ip_repo="$3"; project_name="$4"
case "$stage" in
    step00_preflight|step01_fetch_references) ;;
    step02_hls_covariance) rm -rf ip/custom/doa_covariance_4ch_v4/doa_covariance_4ch_v4_prj "$ip_repo/doa_covariance_4ch_v4" ;;
    step03_hls_spectrum) rm -rf ip/custom/spectrum_power4/spectrum_power4_hls "$ip_repo/spectrum_power4" ;;
    step04_hls_candidate) rm -rf ip/custom/candidate_peak4/candidate_peak4_hls "$ip_repo/candidate_peak4" ;;
    step04_hls_beam) rm -rf ip/custom/beam_weight_4ch/beam_weight_4ch_hls "$ip_repo/beam_weight_4ch" ;;
    step05_hls_repack) rm -rf ip/custom/rfdc_repack4/rfdc_repack4_hls "$ip_repo/rfdc_repack4" ;;
    step05_channelizer) rm -rf "$ip_repo/matlab_channelizer" "$build/v06_gate5_package" ip/model_composer/channelizer/build "$ip_repo/model_composer_channelizer" ;;
    step05_subband_bridge) rm -rf "$ip_repo/doa_subband_bridge_4ch" "$build/subband_bridge_work" "$build/output/doa_subband_bridge_4ch_package.rpt" ;;
    step06_collect_ip) rm -f "$ip_repo/ip_manifest.tsv" ;;
    step07_vivado_project)
        rm -rf "$build/vivado/$project_name"
        rm -f "$build/output/step08_base_bd_inventory.txt" "$build/output/v07_bd_integration.rpt" "$build/output/doa_address_map.txt" \
              "$build/output/ip_status.txt" "$build/output/integrated_block_design.tcl" "$build/output/validation_messages.txt" \
              "$build/output/post_synth_utilization.rpt" "$build/output/post_synth_timing.rpt" \
              "$build/output/post_route_utilization.rpt" "$build/output/post_route_utilization_hierarchical.rpt" \
              "$build/output/post_route_timing.rpt" "$build/output/post_route_drc.rpt" \
              "$build/output/route_status.rpt" "$build/output/timing_gate.txt" ;;
    step08_vivado_integrate)
        rm -f "$build/output/step08_base_bd_inventory.txt" "$build/output/v07_bd_integration.rpt" "$build/output/doa_address_map.txt" ;;
    step09_vivado_validate)
        rm -f "$build/output/ip_status.txt" "$build/output/integrated_block_design.tcl" "$build/output/validation_messages.txt" ;;
    step10_synth)
        rm -f "$build/output/post_synth_utilization.rpt" "$build/output/post_synth_timing.rpt" ;;
    step11_impl)
        rm -f "$build/output/post_route_utilization.rpt" "$build/output/post_route_utilization_hierarchical.rpt" \
              "$build/output/post_route_timing.rpt" "$build/output/post_route_drc.rpt" \
              "$build/output/route_status.rpt" "$build/output/timing_gate.txt" ;;
    step12_bitstream)
        if [[ -d "$build/output" ]]; then find "$build/output" -maxdepth 1 -type f \( -name '*.bit' -o -name '*.hwh' \) -delete; fi ;;
    step13_export_xsa)
        if [[ -d "$build/output" ]]; then find "$build/output" -maxdepth 1 -type f -name '*.xsa' -delete; fi ;;
    step14_hil_vectors) rm -rf "$build/hil_vectors" ;;
    step15_package) rm -rf "$build/release" ;;
    *) echo "ERROR: unknown stage $stage" >&2; exit 2 ;;
esac
rm -f "$build/.stamps/$stage.done" "$build/logs/$stage.log"
echo "Removed products for $stage"
