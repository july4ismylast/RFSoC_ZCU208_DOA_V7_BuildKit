# Vitis HLS build adapter for opfb-fir-to-fft, retargeted to ZCU208 XCZU48DR.
set root [file normalize [file join [file dirname [info script]] ../../..]]
set srcroot [file normalize "$root/upstream/opfb-fir-to-fft"]
set part [expr {[info exists ::env(PART)] ? $::env(PART) : "xczu48dr-fsvg1517-2-e"}]
set clk_ns [expr {[info exists ::env(HLS_CLK_NS)] ? $::env(HLS_CLK_NS) : 2.5}]
open_project -reset fir_to_fft_zcu48dr
add_files "$srcroot/src/datatypes.hpp"
add_files "$srcroot/src/toplevel.cpp"
add_files "$srcroot/src/toplevel.hpp"
set_top fir_to_fft
open_solution -reset solution1
set_part $part
create_clock -period $clk_ns -name default
config_export -description {Reorder and shift OPFB FIR data for FFT} -display_name "fir_to_fft ZU48DR" -format ip_catalog -library mkidgen3 -rtl verilog -vendor MazinLab -version 0.1
csynth_design
export_design
exit
