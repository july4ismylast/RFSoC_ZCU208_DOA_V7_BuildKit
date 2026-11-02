# Vitis HLS build adapter for opfb-fir-cfg, retargeted to ZCU208 XCZU48DR.
# Identity is pinned in config.mk (OPFB_VLNV_OPFB_FIR_CFG) and checked here
# before export; do not let this script invent a different VLNV.
set root [file normalize [file join [file dirname [info script]] ../../..]]
set upstream [expr {[info exists ::env(UPSTREAM)] ? $::env(UPSTREAM) : "$root/upstream"}]
set srcroot [file normalize "$upstream/opfb-fir-cfg"]
set part [expr {[info exists ::env(PART)] ? $::env(PART) : "xczu48dr-fsvg1517-2-e"}]
set clk_ns [expr {[info exists ::env(HLS_CLK_NS)] ? $::env(HLS_CLK_NS) : 2.5}]

set ip_vlnv [expr {[info exists ::env(OPFB_VLNV_OPFB_FIR_CFG)] ? $::env(OPFB_VLNV_OPFB_FIR_CFG) : "mazinlab:mkidgen3:opfb_fir_cfg:1.31"}]
set vlnv_parts [split $ip_vlnv :]
if {[llength $vlnv_parts] != 4 || [lindex $vlnv_parts 2] ne "opfb_fir_cfg"} {
    error "OPFB_VLNV_OPFB_FIR_CFG must be vendor:library:opfb_fir_cfg:version, got '$ip_vlnv'"
}

open_project -reset opfb_fir_cfg_zcu48dr
add_files "$srcroot/src/fir_config.cpp"
add_files "$srcroot/src/fir_config.hpp"
# Upstream script.tcl also names src/fir_confighelp.cpp, but that file is not
# present at the pinned commit; adding it only creates HLS warnings.
set_top opfb_fir_cfg
open_solution -reset solution1
set_part $part
create_clock -period $clk_ns -name default
config_export -description {Generate channel config stream for OPFB FIRs} -display_name "opfb_fir_cfg ZU48DR" -format ip_catalog -library [lindex $vlnv_parts 1] -rtl verilog -vendor [lindex $vlnv_parts 0] -version [lindex $vlnv_parts 3]
csynth_design
export_design
exit
