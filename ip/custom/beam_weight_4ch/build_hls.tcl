# Version-pinned HLS export (V00/V01): part/clock/vendor/library/version all
# come from config.mk variables (exported by the top Makefile).  The env
# defaults below only keep a direct `vitis_hls -f build_hls.tcl` run sane;
# config/ip_versions.tcl builds the BD-side VLNV from the same variables,
# and scripts/collect_ip.sh verifies the result against component.xml.
set part [expr {[info exists ::env(PART)] ? $::env(PART) : "xczu48dr-fsvg1517-2-e"}]
set period [expr {[info exists ::env(PL_CLOCK_PERIOD_NS)] ? $::env(PL_CLOCK_PERIOD_NS) : "7.8125"}]
set ip_vendor [expr {[info exists ::env(CUSTOM_IP_VENDOR)] ? $::env(CUSTOM_IP_VENDOR) : "openai"}]
set ip_library [expr {[info exists ::env(CUSTOM_IP_LIBRARY)] ? $::env(CUSTOM_IP_LIBRARY) : "doa"}]
# Keep the version as a Tcl *string*.  Do not select it with expr{}: the
# Tcl 8.5 embedded in Vivado/Vitis can give a numeric-looking expr result a
# double internal representation, which export then serializes as
# 7.0999999999999996 instead of the pinned 7.1.
set ip_version "2.1"
if {[info exists ::env(IPVER_BEAM)] && [string trim $::env(IPVER_BEAM)] ne ""} {
    set ip_version [string trim $::env(IPVER_BEAM)]
}
if {![regexp {^[0-9]+\.[0-9]+$} $ip_version]} {
    error "IPVER_BEAM must be a major.minor version string, got '$ip_version'"
}
open_project -reset beam_weight_4ch_hls
add_files src/beam_weight_4ch.cpp -cflags "-Isrc"
add_files -tb tb/beam_weight_4ch_tb.cpp -cflags "-Isrc"
set_top beam_weight_4ch
open_solution -reset solution1
set_part $part
create_clock -period $period -name default
config_export -format ip_catalog -rtl verilog -vendor $ip_vendor -library $ip_library -version $ip_version -display_name "Four-Lane Four-Channel Complex Beam Monitor"
csim_design
csynth_design
export_design
exit
