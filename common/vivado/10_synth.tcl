set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir common.tcl]
open_work_project
set jobs [expr {[info exists ::env(JOBS)] ? $::env(JOBS) : 8}]
set bd_files [get_files -quiet -all *.bd]
if {[llength $bd_files]} { generate_target all $bd_files }
reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
require_successful_run synth_1
open_run synth_1
set output [ensure_output_directory]
report_utilization -file [file join $output post_synth_utilization.rpt]
report_timing_summary -file [file join $output post_synth_timing.rpt]
puts "Synthesis passed"
close_project

