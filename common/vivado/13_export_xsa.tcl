set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir common.tcl]
open_work_project
require_successful_run impl_1
set output [ensure_output_directory]
set xsa [file join $output [require_env PROJECT_NAME].xsa]
write_hw_platform -fixed -include_bit -force -file $xsa
if {![file exists $xsa]} { error "write_hw_platform did not create $xsa" }
puts "Created $xsa"
close_project

