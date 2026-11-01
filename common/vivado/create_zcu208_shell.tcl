# DEPRECATED -- NOT part of the production DOA V7 flow.
# Minimal PS/reset-only shell kept only so old projects/*_reference inspection
# commands fail loudly with context instead of producing something that looks
# like a ZCU208 port.  It does NOT configure RFDC, clocks, MTS, XDC or a
# wrapper.  Production hardware starts from the pinned RFSoC-MTS base
# (BASE_KIND=mts, stage V03).  IP here is still version-pinned (project rule:
# no VLNV wildcards anywhere, even in deprecated helpers).
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir common.tcl]
doa_require_vivado_lock
puts "WARNING: create_zcu208_shell.tcl is DEPRECATED (PS/reset placeholder only, no RFDC/MTS). Use the RFSoC-MTS base flow (stage V03)."

set proj "zcu208_shell"
set part $::PART_PINNED
set board_part $::BOARD_PART_PINNED
if {[llength $argv] > 0} { set proj [lindex $argv 0] }
if {[llength $argv] > 1 && [lindex $argv 1] ne ""} { set part [lindex $argv 1] }
if {[llength $argv] > 2 && [lindex $argv 2] ne ""} { set board_part [lindex $argv 2] }
if {$part ne $::PART_PINNED} {
    error "Refusing shell for part $part; pinned ZCU208 part is $::PART_PINNED"
}
create_project -force $proj [file normalize "build/$proj"] -part $part
set_property BOARD_PART $board_part [current_project]
create_bd_design design_1
doa_create_pinned_ip ps zynq_ultra_ps_e_0
catch {apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} [get_bd_cells zynq_ultra_ps_e_0]}
doa_create_pinned_ip proc_sys_reset rst_pl
puts "Created DEPRECATED minimal shell for $part. RFDC tile/sample-rate/MTS settings must come from the pinned RFSoC-MTS base, not from this file."
save_bd_design
