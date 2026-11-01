# Minimal ZCU208/XCzu48DR IP-Integrator shell.
# Intentionally does NOT guess RF Data Converter settings. Import/source a verified ZCU208
# RFDC/MTS/base Tcl from RFSoC-MTS or RFSoC-PYNQ, then insert algorithm IPs.
set proj "zcu208_shell"
set part "xczu48dr-fsvg1517-2-e"
set board_part ""
if {[llength $argv] > 0} { set proj [lindex $argv 0] }
if {[llength $argv] > 1} { set part [lindex $argv 1] }
if {[llength $argv] > 2} { set board_part [lindex $argv 2] }
create_project -force $proj [file normalize "build/$proj"] -part $part
if {$board_part ne ""} { catch {set_property BOARD_PART $board_part [current_project]} }
create_bd_design design_1
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* zynq_ultra_ps_e_0
catch {apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} [get_bd_cells zynq_ultra_ps_e_0]}
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* rst_pl
puts "Created minimal ZCU208 shell for $part. RFDC tile/sample-rate/MTS settings must come from a verified ZCU208 reference design."
save_bd_design
