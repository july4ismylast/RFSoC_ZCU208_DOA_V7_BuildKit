set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir common.tcl]
open_work_project
require_successful_run synth_1
set jobs [expr {[info exists ::env(JOBS)] ? $::env(JOBS) : 8}]
set impl_run [get_runs impl_1]
set cur_strategy [get_property STRATEGY $impl_run]
if {$cur_strategy ne "Performance_ExtraTimingOpt"} {
    puts "Setting impl_1 strategy to Performance_ExtraTimingOpt (was $cur_strategy)"
    set_property strategy Performance_ExtraTimingOpt $impl_run
}
reset_run impl_1
set pr_phys_en [get_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED $impl_run]
set target_step [expr {($pr_phys_en eq "1" || $pr_phys_en eq "true" || $pr_phys_en eq "TRUE") ? "post_route_phys_opt_design" : "route_design"}]
puts "Launching impl_1 to_step=$target_step (strategy=[get_property STRATEGY $impl_run])"
launch_runs impl_1 -to_step $target_step -jobs $jobs
wait_on_run impl_1
require_successful_run impl_1
open_run impl_1
set output [ensure_output_directory]
report_utilization -file [file join $output post_route_utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 4 -file [file join $output post_route_utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -file [file join $output post_route_timing.rpt]
report_route_status -file [file join $output route_status.rpt]
report_drc -file [file join $output post_route_drc.rpt]
set setup_paths [get_timing_paths -quiet -delay_type max -max_paths 1 -nworst 1]
if {[llength $setup_paths] == 0} { error "No setup timing path was available after routing" }
set worst_slack [get_property SLACK [lindex $setup_paths 0]]
set hold_paths [get_timing_paths -quiet -delay_type min -max_paths 1 -nworst 1]
set worst_hold [expr {[llength $hold_paths] > 0 ? [get_property SLACK [lindex $hold_paths 0]] : 0.0}]
set file [open [file join $output timing_gate.txt] w]
puts $file "WNS=$worst_slack"
puts $file "WHS=$worst_hold"
close $file
if {$worst_slack < 0.0} { error "Timing gate failed: WNS=$worst_slack ns (WHS=$worst_hold ns)" }
if {$worst_hold < 0.0}  { error "Hold timing gate failed: WHS=$worst_hold ns (WNS=$worst_slack ns)" }
puts "Implementation passed timing with WNS=$worst_slack ns, WHS=$worst_hold ns"
close_project
invalidate_downstream_stamps {
    step12_bitstream.done
    step13_export_xsa.done
    step15_package.done
}

