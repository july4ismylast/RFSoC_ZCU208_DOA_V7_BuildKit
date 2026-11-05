set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir common.tcl]
open_work_project
set jobs [expr {[info exists ::env(JOBS)] ? $::env(JOBS) : 8}]
# `-all *.bd` also returns generated nested IP sub-designs (for example,
# the DDR4 controller's bd_*.bd). Vivado 2023.2 rejects generating those
# independently; generate targets for the selected top-level base BD only.
set base_bd [require_env BASE_BD]
set bd_files [get_files -quiet -all */${base_bd}.bd]
if {[llength $bd_files] != 1} {
    error "Expected exactly one top-level BD named ${base_bd}.bd; found: $bd_files"
}
puts "Generating targets for top-level BD [lindex $bd_files 0]"
generate_target all [lindex $bd_files 0]
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

