set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir common.tcl]
open_work_project
select_base_bd
validate_bd_design
save_bd_design
set output [ensure_output_directory]
report_ip_status -file [file join $output ip_status.txt]
write_bd_tcl -force [file join $output integrated_block_design.tcl]
# Vivado 2023.2 has no `get_messages` Tcl command. validate_bd_design and
# report_ip_status emit their diagnostics directly to the Vivado run log, which
# run_stage.sh preserves as step09_vivado_validate.log.
set file [open [file join $output validation_messages.txt] w]
puts $file "Full Vivado validation diagnostics are in build/logs/step09_vivado_validate.log."
puts $file "This note is used instead of the unavailable get_messages command in Vivado 2023.2."
close $file
# No "save_project" Tcl command exists in Vivado; save_bd_design above is
# the persistence operation for BD state.
puts "BD validation passed; reports are in $output"
close_project

