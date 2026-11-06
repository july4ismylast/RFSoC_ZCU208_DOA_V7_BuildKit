# Version-pinned HLS export for the V07 phase interferometer (V00/V01 rules:
# part/clock/vendor/library/version all come from config.mk).  The env defaults
# below only keep a direct `vitis_hls -f build_hls.tcl` run sane;
# config/ip_versions.tcl builds the BD-side VLNV from the same variables, and
# scripts/collect_ip.sh verifies the result against component.xml.
set part [expr {[info exists ::env(PART)] ? $::env(PART) : "xczu48dr-fsvg1517-2-e"}]
set period [expr {[info exists ::env(PL_CLOCK_PERIOD_NS)] ? $::env(PL_CLOCK_PERIOD_NS) : "7.8125"}]
set ip_vendor [expr {[info exists ::env(CUSTOM_IP_VENDOR)] ? $::env(CUSTOM_IP_VENDOR) : "openai"}]
set ip_library [expr {[info exists ::env(CUSTOM_IP_LIBRARY)] ? $::env(CUSTOM_IP_LIBRARY) : "doa"}]
# Keep the version as a Tcl *string*: expr{} can turn 1.0 into a double and
# export then serializes 0.9999999999999999 (see doa_covariance build_hls.tcl).
set ip_version "1.0"
if {[info exists ::env(IPVER_PHASE_INTERF)] && [string trim $::env(IPVER_PHASE_INTERF)] ne ""} {
    set ip_version [string trim $::env(IPVER_PHASE_INTERF)]
}
if {![regexp {^[0-9]+\.[0-9]+$} $ip_version]} {
    error "IPVER_PHASE_INTERF must be a major.minor version string, got '$ip_version'"
}

open_project -reset phase_interf_4ch_prj
set_top phase_interf_4ch
add_files src/phase_interf_4ch.cpp -cflags "-Isrc"
add_files -tb tb/phase_interf_4ch_tb.cpp -cflags "-Isrc"
open_solution -reset solution1
set_part $part
create_clock -period $period -name default
config_export -format ip_catalog -rtl verilog -vendor $ip_vendor -library $ip_library -version $ip_version -display_name "DOA V7 Phase Interferometry 4ch"
csim_design
csynth_design
export_design
exit
