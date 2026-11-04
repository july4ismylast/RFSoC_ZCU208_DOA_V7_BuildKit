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
puts "OPFB physical screen source run: $checkpoint"
set project [file join [file dirname $checkpoint] opfb_eval.xpr]
if {![file isfile $project]} { error "Evaluation project missing: $project" }
open_project $project
set bd [get_files -quiet */opfb_eval.bd]
if {[llength $bd] != 1} { error "Expected one OPFB evaluation BD: $bd" }
open_bd_design [lindex $bd 0]
foreach {name expected} {istream_V_0 16 qstream_V_0 16 output_r_0 64} {
    set bytes [get_property CONFIG.TDATA_NUM_BYTES [get_bd_intf_ports $name]]
    if {$bytes ne "$expected"} { error "Refusing invalid stream width $name: $bytes bytes (expected $expected)" }
}
set work [file join [file dirname $checkpoint] physical_[clock microseconds]]
file mkdir $work
# The normal synthesis checkpoint contains package I/O buffers (892 IOBs).
# Re-synthesize the existing generated sources in real out-of-context mode;
# do not assign internal AXI streams to package pins or suppress I/O DRCs.
update_compile_order -fileset sources_1
synth_design -top opfb_eval_wrapper -part [require_env PART] -mode out_of_context
set buffers [get_cells -quiet -hierarchical -filter {REF_NAME =~ IBUF* || REF_NAME =~ OBUF* || REF_NAME =~ IOBUF*}]
if {[llength $buffers]} { error "OOC synthesis still contains package I/O buffers: $buffers" }
set blackboxes [get_cells -quiet -hierarchical -filter {IS_BLACKBOX == 1}]
if {[llength $blackboxes]} { error "OOC synthesis has unresolved black boxes: $blackboxes" }
write_checkpoint [file join $work opfb_eval_true_ooc_synth.dcp]
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
