# Vitis HLS build adapter for opfb-fir-cfg, retargeted to ZCU208 XCZU48DR.
set root [file normalize [file join [file dirname [info script]] ../../..]]
set srcroot [file normalize "$root/upstream/opfb-fir-cfg"]
set part [expr {[info exists ::env(PART)] ? $::env(PART) : "xczu48dr-fsvg1517-2-e"}]
set clk_ns [expr {[info exists ::env(HLS_CLK_NS)] ? $::env(HLS_CLK_NS) : 2.5}]
open_project -reset opfb_fir_cfg_zcu48dr
add_files "$srcroot/src/fir_config.cpp"
add_files "$srcroot/src/fir_config.hpp"
add_files "$srcroot/src/fir_confighelp.cpp"
set_top opfb_fir_cfg
open_solution -reset solution1
set_part $part
create_clock -period $clk_ns -name default
config_export -description {Generate channel config stream for OPFB FIRs} -display_name "opfb_fir_cfg ZU48DR" -format ip_catalog -library mkidgen3 -rtl verilog -vendor MazinLab -version 0.2
csynth_design
export_design
exit
