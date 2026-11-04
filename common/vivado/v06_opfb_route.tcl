# Standalone physical feasibility screen; never opens the MTS project.
source [file join [file dirname [file normalize [info script]]] common.tcl]
doa_require_vivado_lock
set build [file normalize [require_env BUILD]]
set output [ensure_output_directory]
set checkpoints [glob -nocomplain [file join $build opfb_ooc run_* opfb_eval_synth.dcp]]
if {![llength $checkpoints]} { error "No completed OPFB synthesis checkpoint. Run make opfb-resource-check first." }
# Sort by modification time, not lexical run-name ordering.
set checkpoint [lindex $checkpoints 0]
foreach candidate $checkpoints {
    if {[file mtime $candidate] > [file mtime $checkpoint]} { set checkpoint $candidate }
}
puts "OPFB physical screen input: $checkpoint"
open_checkpoint $checkpoint
set work [file join [file dirname $checkpoint] physical_[clock microseconds]]
file mkdir $work
# This is an isolated top with evaluation ports, not board pin assignments.
# No bitstream is generated; final deployment still needs real integration.
opt_design
place_design
phys_opt_design
route_design
report_utilization -file [file join $output v06_opfb_routed_utilization.rpt]
report_utilization -hierarchical -file [file join $output v06_opfb_routed_utilization_hierarchical.rpt]
report_timing_summary -report_unconstrained -file [file join $output v06_opfb_routed_timing.rpt]
report_route_status -file [file join $output v06_opfb_route_status.rpt]
report_drc -file [file join $output v06_opfb_routed_drc.rpt]
write_checkpoint [file join $work opfb_eval_routed.dcp]
puts "Physical screen reports written. Review setup, hold, route status, DRC and unconstrained I/O. Not production signoff."
close_design
