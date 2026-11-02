# Version-pinned HLS export (V00/V01/V05): part/clock/vendor/library/version
# all come from config.mk variables (exported by the top Makefile).  This is
# a *wideband* IP: its clock is WIDEBAND_CLOCK_PERIOD_NS (4.0 ns = 250 MHz,
# the V04 RFDC fabric contract), NOT the low-rate PL_CLOCK_PERIOD_NS used by
# the 125/128 MHz DOA-side IPs.  config/ip_versions.tcl builds the BD-side
# VLNV from the same variables, and scripts/collect_ip.sh verifies the
# result against component.xml.
set part [expr {[info exists ::env(PART)] ? $::env(PART) : "xczu48dr-fsvg1517-2-e"}]
set period [expr {[info exists ::env(WIDEBAND_CLOCK_PERIOD_NS)] ? $::env(WIDEBAND_CLOCK_PERIOD_NS) : "4.0"}]
set ip_vendor [expr {[info exists ::env(CUSTOM_IP_VENDOR)] ? $::env(CUSTOM_IP_VENDOR) : "openai"}]
set ip_library [expr {[info exists ::env(CUSTOM_IP_LIBRARY)] ? $::env(CUSTOM_IP_LIBRARY) : "doa"}]
# Keep the version as a Tcl *string* (see spectrum_power4/build_hls.tcl for
# why an expr{} selection can serialize 1.0 as a long double fraction).
set ip_version "1.0"
if {[info exists ::env(IPVER_RFDC_REPACK4)] && [string trim $::env(IPVER_RFDC_REPACK4)] ne ""} {
    set ip_version [string trim $::env(IPVER_RFDC_REPACK4)]
}
if {![regexp {^[0-9]+\.[0-9]+$} $ip_version]} {
    error "IPVER_RFDC_REPACK4 must be a major.minor version string, got '$ip_version'"
}
open_project -reset rfdc_repack4_hls
add_files src/rfdc_repack4.cpp -cflags "-Isrc"
add_files -tb tb/rfdc_repack4_tb.cpp -cflags "-Isrc"
set_top rfdc_repack4
open_solution -reset solution1
set_part $part
create_clock -period $period -name default
config_export -format ip_catalog -rtl verilog -vendor $ip_vendor -library $ip_library -version $ip_version -display_name "RFDC Four-Channel SSR-8 I/Q Repack"
csim_design
csynth_design
export_design
exit
