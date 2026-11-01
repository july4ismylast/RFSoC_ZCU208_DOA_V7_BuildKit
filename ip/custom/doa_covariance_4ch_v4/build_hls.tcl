# Version-pinned HLS export (V00/V01): part/clock/vendor/library/version all
# come from config.mk variables (exported by the top Makefile).  The env
# defaults below only keep a direct `vitis_hls -f build_hls.tcl` run sane;
# config/ip_versions.tcl builds the BD-side VLNV from the same variables,
# and scripts/collect_ip.sh verifies the result against component.xml.
set part [expr {[info exists ::env(PART)] ? $::env(PART) : "xczu48dr-fsvg1517-2-e"}]
set period [expr {[info exists ::env(PL_CLOCK_PERIOD_NS)] ? $::env(PL_CLOCK_PERIOD_NS) : "7.8125"}]
set ip_vendor [expr {[info exists ::env(CUSTOM_IP_VENDOR)] ? $::env(CUSTOM_IP_VENDOR) : "openai"}]
set ip_library [expr {[info exists ::env(CUSTOM_IP_LIBRARY)] ? $::env(CUSTOM_IP_LIBRARY) : "doa"}]
set ip_version [expr {[info exists ::env(IPVER_COVARIANCE)] ? $::env(IPVER_COVARIANCE) : "7.1"}]
open_project -reset doa_covariance_4ch_v4_prj
set_top doa_covariance_4ch_v4
add_files src/doa_covariance_4ch_v4.cpp -cflags "-Isrc"
add_files -tb tb/doa_covariance_4ch_v4_tb.cpp -cflags "-Isrc"
open_solution -reset solution1
set_part $part
create_clock -period $period -name default
config_export -format ip_catalog -rtl verilog -vendor $ip_vendor -library $ip_library -version $ip_version -display_name "DOA V7 Four-Lane Covariance"
csim_design
csynth_design
export_design
exit
