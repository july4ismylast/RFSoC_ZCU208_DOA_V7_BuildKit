set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir common.tcl]
open_work_project
require_successful_run impl_1
open_run impl_1
set output [ensure_output_directory]
set bit_file [file join $output [require_env PROJECT_NAME].bit]
write_bitstream -force $bit_file
set hwh_files [get_files -quiet -all *.hwh]
foreach hwh $hwh_files { file copy -force $hwh [file join $output [file tail $hwh]] }
if {![file exists $bit_file]} { error "write_bitstream did not create $bit_file" }
puts "Created $bit_file"
close_project

