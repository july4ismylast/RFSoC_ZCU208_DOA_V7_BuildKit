# Vitis HLS build adapter for opfb-fir-to-fft, retargeted to ZCU208 XCZU48DR.
# Identity is pinned in config.mk (OPFB_VLNV_FIR_TO_FFT) and checked here
# before export; do not let this script invent a different VLNV.
set root [file normalize [file join [file dirname [info script]] ../../..]]
set upstream [expr {[info exists ::env(UPSTREAM)] ? $::env(UPSTREAM) : "$root/upstream"}]
set srcroot [file normalize "$upstream/opfb-fir-to-fft"]
set part [expr {[info exists ::env(PART)] ? $::env(PART) : "xczu48dr-fsvg1517-2-e"}]
set clk_ns [expr {[info exists ::env(HLS_CLK_NS)] ? $::env(HLS_CLK_NS) : 2.5}]

set ip_vlnv [expr {[info exists ::env(OPFB_VLNV_FIR_TO_FFT)] ? $::env(OPFB_VLNV_FIR_TO_FFT) : "mazinlab:mkidgen3:fir_to_fft:1.31"}]
set vlnv_parts [split $ip_vlnv :]
if {[llength $vlnv_parts] != 4 || [lindex $vlnv_parts 2] ne "fir_to_fft"} {
    error "OPFB_VLNV_FIR_TO_FFT must be vendor:library:fir_to_fft:version, got '$ip_vlnv'"
}

open_project -reset fir_to_fft_zcu48dr
add_files "$srcroot/src/datatypes.hpp"
add_files "$srcroot/src/toplevel.cpp"
add_files "$srcroot/src/toplevel.hpp"
set_top fir_to_fft
open_solution -reset solution1
set_part $part
create_clock -period $clk_ns -name default
config_export -description {Reorder and shift OPFB FIR data for FFT} -display_name "fir_to_fft ZU48DR" -format ip_catalog -library [lindex $vlnv_parts 1] -rtl verilog -vendor [lindex $vlnv_parts 0] -version [lindex $vlnv_parts 3]
csynth_design
export_design
exit
