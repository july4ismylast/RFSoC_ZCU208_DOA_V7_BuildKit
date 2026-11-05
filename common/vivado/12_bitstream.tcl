set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir common.tcl]
open_work_project
require_successful_run impl_1
set jobs [expr {[info exists ::env(JOBS)] ? $::env(JOBS) : 8}]
set impl_run [get_runs impl_1]
set status [get_property STATUS $impl_run]
if {![string match "*write_bitstream Complete*" $status]} {
    launch_runs impl_1 -to_step write_bitstream -jobs $jobs
    wait_on_run impl_1
    require_successful_run impl_1
}
set output [ensure_output_directory]
set bit_file [file join $output [require_env PROJECT_NAME].bit]
set impl_dir [get_property DIRECTORY $impl_run]
set run_bits [glob -nocomplain -directory $impl_dir *.bit]
if {[llength $run_bits] > 0} {
    file copy -force [lindex $run_bits 0] $bit_file
} else {
    open_run impl_1
    write_bitstream -force $bit_file
    set top_name [get_property TOP [current_fileset]]
    if {$top_name ne ""} {
        file copy -force $bit_file [file join $impl_dir "${top_name}.bit"]
    }
}
set hwh_files [get_files -quiet -all *.hwh]
foreach hwh $hwh_files { file copy -force $hwh [file join $output [file tail $hwh]] }
if {![file exists $bit_file]} { error "write_bitstream did not create $bit_file" }
puts "Created $bit_file"
close_project
