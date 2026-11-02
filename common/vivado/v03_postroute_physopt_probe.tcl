# Stage V03 diagnostic (non-destructive): can post-route phys_opt_design close
# the residual timing miss of the *unmodified* RFSoC-MTS base in Vivado 2023.2?
#
# First V03 run (2026-11-02): mts.tcl + synth + impl + write_bitstream all
# completed with only the PS 3.4->3.5 adaptation, but the routed timing
# summary ended at WNS=-0.017 ns / TNS=-0.050 ns / WHS=+0.010 ns in clock
# clk_out1_mts_MTSclkwiz_0 (500 MHz clkRF), worst endpoints in deepCapture
# (axis_data_fifo_adc / axis_dwidth_converter, fed by RFDC m12_axis).  The
# router's built-in physical synthesis already improved WNS -0.180 -> -0.017.
# This probe opens the routed checkpoint IN MEMORY (the project is not
# touched), runs one post-route phys_opt_design, and reports whether setup
# timing closes.  Only if it does will the post-route phys-opt step be
# encoded into scripts/prepare_mts_2023p2_patch.sh and V03 re-run cleanly.
#
# Usage (from build/mts_base_src_2023p2/boards/ZCU208/build_mts):
#   vivado -mode batch -source ../../../../common/vivado/v03_postroute_physopt_probe.tcl \
#       [-tclargs [routed.dcp] [directive] [output_prefix]]
# Defaults: ./mts/mts.runs/impl_1/mts_wrapper_routed.dcp, AggressiveExplore,
#           $HOME/mts_v03_physopt_probe

set running [version -short]
if {[string first "2023.2" $running] == -1} {
    error "V03 probe: this flow is locked to Vivado 2023.2, running $running"
}

set dcp "./mts/mts.runs/impl_1/mts_wrapper_routed.dcp"
if {$argc >= 1} { set dcp [lindex $argv 0] }
set directive "AggressiveExplore"
if {$argc >= 2} { set directive [lindex $argv 1] }
if {$argc >= 3} {
    set out_prefix [lindex $argv 2]
} elseif {[info exists ::env(HOME)]} {
    set out_prefix [file join $::env(HOME) "mts_v03_physopt_probe"]
} else {
    set out_prefix "./mts_v03_physopt_probe"
}

if {![file exists $dcp]} {
    error "V03 probe: routed checkpoint not found: $dcp\nRun the V03 impl first (make bitstream in boards/ZCU208/build_mts), then re-run this probe."
}

proc worst_setup_slack_ns {} {
    set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
    if {[llength $paths] == 0} { return "NA" }
    return [get_property SLACK $paths]
}

puts "PROBE: opening routed checkpoint $dcp"
open_checkpoint $dcp
set slack_before [worst_setup_slack_ns]
puts "PROBE RESULT before: worst setup slack = $slack_before ns"
report_timing_summary -max_paths 10 -report_unconstrained -file "${out_prefix}_before.rpt"

puts "PROBE: phys_opt_design -directive $directive"
phys_opt_design -directive $directive
set slack_after [worst_setup_slack_ns]
puts "PROBE RESULT after:  worst setup slack = $slack_after ns"
report_timing_summary -max_paths 10 -report_unconstrained -file "${out_prefix}_after.rpt"
report_route_status -file "${out_prefix}_route_status.rpt"
write_checkpoint -force "${out_prefix}_postroute_physopt.dcp"
close_design

puts "PROBE reports: ${out_prefix}_before.rpt | ${out_prefix}_after.rpt | ${out_prefix}_route_status.rpt"
if {$slack_after ne "NA" && $slack_after < 0} {
    error "PROBE RESULT: FAIL -- post-route phys_opt_design ($directive) did not close timing (worst setup slack $slack_after ns). Send ${out_prefix}_after.rpt timing summary; next lever is an Explore-class implementation strategy, still implementation-only."
}
puts "PROBE RESULT: PASS -- post-route phys_opt_design ($directive) closes setup timing (worst setup slack $slack_after ns)."
