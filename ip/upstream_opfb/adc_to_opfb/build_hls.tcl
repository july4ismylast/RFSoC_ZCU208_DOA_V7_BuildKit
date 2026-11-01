# Vitis HLS build adapter for adc-to-opfb, retargeted to ZCU208 XCZU48DR.
set root [file normalize [file join [file dirname [info script]] ../../..]]
set srcroot [file normalize "$root/upstream/adc-to-opfb"]
set part [expr {[info exists ::env(PART)] ? $::env(PART) : "xczu48dr-fsvg1517-2-e"}]
set clk_ns [expr {[info exists ::env(HLS_CLK_NS)] ? $::env(HLS_CLK_NS) : 2.5}]
open_project -reset adc_to_opfb_zcu48dr
add_files "$srcroot/src/toplevel.hpp"
add_files "$srcroot/src/toplevel.cpp"
add_files "$srcroot/src/datatypes.hpp"
set_top adc_to_opfb
open_solution -reset solution1
set_part $part
create_clock -period $clk_ns -name default
config_export -description {Package ADC data for OPFB FIRs} -display_name "adc_to_opfb ZU48DR" -format ip_catalog -library mkidgen3 -rtl verilog -vendor MazinLab -version 0.1
csynth_design
export_design
exit
