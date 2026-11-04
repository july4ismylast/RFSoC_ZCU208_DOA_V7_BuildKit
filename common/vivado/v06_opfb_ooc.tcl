# Native one-instance OPFB evaluation only. No MTS project is opened.
source [file join [file dirname [file normalize [info script]]] common.tcl]
doa_require_vivado_lock
set build [file normalize [require_env BUILD]]
set upstream [file normalize [require_env UPSTREAM]]
set output [ensure_output_directory]
set src [file join $upstream RFSoC_OPFB bd opfb_streaming.tcl]
if {![file isfile $src]} { error "Missing pinned OPFB source: $src" }
set f [open $src r]; set text [read $f]; close $f
# Extract only hierarchy definitions; never execute the upstream board/root
# design or its 2022.1 project creation/version guard.
set first [string first "proc create_hier_cell_firs " $text]
set last [string first "proc create_hier_cell_switchboard " $text]
if {$first < 0 || $last <= $first} { error "Unexpected upstream hierarchy layout" }
set definitions [string range $text $first [expr {$last-1}]]
for {set lane 0} {$lane < 16} {incr lane} {
    set old "../../../../../../../../filter/4_tap_equiripple/lane${lane}.coe"
    set coe [file join $upstream RFSoC_OPFB filter 4_tap_equiripple lane${lane}.coe]
    if {![file isfile $coe]} { error "Missing pinned coefficient file: $coe" }
    if {[string first $old $definitions] < 0} { error "Missing coefficient reference for lane $lane" }
    set definitions [string map [list $old $coe] $definitions]
}
# The 2023.2 HLS exports name the ADC interfaces istream/qstream;
# the old board Tcl expects istream_V/qstream_V. These two names are
# confirmed by the uploaded step05 catalog log, not substring discovery.
foreach {old new} {
    adc_to_opfb_0/istream_V adc_to_opfb_0/istream
    adc_to_opfb_0/qstream_V adc_to_opfb_0/qstream
} {
    if {[string first "\[get_bd_intf_pins $old\]" $definitions] < 0} {
        error "Expected legacy ADC interface reference missing: $old"
    }
    set definitions [string map [list "\[get_bd_intf_pins $old\]" "\[get_bd_intf_pins $new\]"] $definitions]
}
# Keep every evaluation attempt rather than deleting or overwriting a failed
# project. No change to BUILD, the packaged IP repository, or the MTS copy.
set eval_dir [file join $build opfb_ooc run_[clock microseconds]]
create_project opfb_eval $eval_dir -part [require_env PART]
set_property target_language Verilog [current_project]
doa_append_ip_repo_paths [list [file normalize [require_env IP_REPO]]]
set script_folder [file dirname $src]
create_bd_design opfb_eval
eval $definitions
create_hier_cell_opfb / opfb
foreach pin [get_bd_intf_pins /opfb/*] { make_bd_intf_pins_external $pin }
# Only the two standalone scalar pins may be externalized separately.
# get_bd_pins /opfb/* also returns AXI member pins; externalizing those
# overrides interface connections and can collapse propagated buses to 1 bit.
foreach name {ap_clk ap_rst_n} {
    make_bd_pins_external [get_bd_pins /opfb/$name]
}
set clk [get_bd_ports -filter {TYPE == clk}]
if {[llength $clk] != 1} { error "Expected one OPFB evaluation clock: $clk" }
set_property CONFIG.FREQ_HZ 250000000 $clk
assign_bd_address
validate_bd_design
# Fail before synthesis if a streaming data interface has collapsed to scalar.
set width_report [open [file join $output v06_opfb_interface_widths.rpt] w]
foreach interface {istream_V_0 qstream_V_0 output_r_0} {
    set port [get_bd_intf_ports -quiet $interface]
    if {[llength $port] != 1} {
        close $width_report
        error "Expected one external stream interface $interface; found: $port"
    }
    set bytes [get_property CONFIG.TDATA_NUM_BYTES $port]
    puts $width_report "$interface TDATA_NUM_BYTES=$bytes"
    if {![string is integer -strict $bytes] || $bytes <= 1} {
        close $width_report
        error "Invalid stream width on $interface: TDATA_NUM_BYTES=$bytes"
    }
}
close $width_report
save_bd_design
set bd [get_files */opfb_eval.bd]
generate_target all $bd
set wrappers [make_wrapper -files $bd -top]
add_files -norecurse $wrappers
set_property top opfb_eval_wrapper [current_fileset]
update_compile_order -fileset sources_1
set xdc [file join $eval_dir opfb_eval.xdc]
set f [open $xdc w]
puts $f "create_clock -name opfb_eval_clk -period 4.000 \[get_ports [get_property NAME $clk]\]"
close $f
add_files -fileset constrs_1 $xdc
launch_runs synth_1 -jobs [require_env JOBS]
wait_on_run synth_1
require_successful_run synth_1
open_run synth_1
set blackboxes [get_cells -hierarchical -filter {IS_BLACKBOX == 1}]
if {[llength $blackboxes]} { error "Incomplete OPFB synthesis: black boxes remain: $blackboxes" }
report_utilization -file [file join $output v06_opfb_ooc_utilization.rpt]
report_utilization -hierarchical -file [file join $output v06_opfb_ooc_utilization_hierarchical.rpt]
report_timing_summary -report_unconstrained -file [file join $output v06_opfb_ooc_timing.rpt]
write_checkpoint [file join $eval_dir opfb_eval_synth.dcp]
puts "Native SSR16/4096 OPFB synthesis reports written. Not an SSR8/1024 adapter, four-channel fit, or routed timing signoff."
close_project
