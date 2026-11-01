set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir common.tcl]
open_work_project
select_base_bd
validate_bd_design
save_bd_design
set output [ensure_output_directory]
report_ip_status -file [file join $output ip_status.txt]
write_bd_tcl -force [file join $output integrated_block_design.tcl]
set messages [get_messages -severity {CRITICAL WARNING ERROR}]
set file [open [file join $output validation_messages.txt] w]
foreach message $messages { puts $file $message }
close $file
save_project
puts "BD validation passed; reports are in $output"
close_project

