# Vitis HLS build adapter for adc-to-opfb, retargeted to ZCU208 XCZU48DR.
# Identity is pinned in config.mk (OPFB_VLNV_ADC_TO_OPFB) and checked here
# before export; do not let this script invent a different VLNV.
set root [file normalize [file join [file dirname [info script]] ../../..]]
set upstream [expr {[info exists ::env(UPSTREAM)] ? $::env(UPSTREAM) : "$root/upstream"}]
set srcroot [file normalize "$upstream/adc-to-opfb"]
set part [expr {[info exists ::env(PART)] ? $::env(PART) : "xczu48dr-fsvg1517-2-e"}]
set clk_ns [expr {[info exists ::env(HLS_CLK_NS)] ? $::env(HLS_CLK_NS) : 2.5}]

set ip_vlnv [expr {[info exists ::env(OPFB_VLNV_ADC_TO_OPFB)] ? $::env(OPFB_VLNV_ADC_TO_OPFB) : "mazinlab:mkidgen3:adc_to_opfb:1.32"}]
set vlnv_parts [split $ip_vlnv :]
if {[llength $vlnv_parts] != 4 || [lindex $vlnv_parts 2] ne "adc_to_opfb"} {
    error "OPFB_VLNV_ADC_TO_OPFB must be vendor:library:adc_to_opfb:version, got '$ip_vlnv'"
}

open_project -reset adc_to_opfb_zcu48dr
add_files "$srcroot/src/toplevel.hpp"
add_files "$srcroot/src/toplevel.cpp"
add_files "$srcroot/src/datatypes.hpp"
set_top adc_to_opfb
open_solution -reset solution1
set_part $part
create_clock -period $clk_ns -name default
config_export -description {Package ADC data for OPFB FIRs} -display_name "adc_to_opfb ZU48DR" -format ip_catalog -library [lindex $vlnv_parts 1] -rtl verilog -vendor [lindex $vlnv_parts 0] -version [lindex $vlnv_parts 3]
csynth_design
export_design
exit
