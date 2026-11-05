# V06 Gate 4: isolated AXI4-Stream wrapper candidate OOC synthesis.
# This is not IP packaging, a BD change, or production timing signoff.
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir .. .. ..]]
source [file join $root_dir config ip_versions.tcl]
set report_file [file join $::env(BUILD) output v06_gate4_axis_wrapper_ooc.rpt]
set work_dir [file join $::env(BUILD) v06_gate4_axis_wrapper_ooc]
set gate1_report [file join $::env(BUILD) output v06_gate1_hdl_generation_transposed.rpt]
set gate3_report [file join $::env(BUILD) output v06_gate3_transposed_numerics.rpt]
set rtl_root [file join $script_dir hdl_prj hdlsrc_transposed zu48dr_channelizer_ip]
set wrapper_file [file join $script_dir channelizer_axis_wrapper.sv]
set xdc_file [file join $script_dir v06_gate4_axis_wrapper_ooc.xdc]
file mkdir [file dirname $report_file]
file mkdir $work_dir
set report_fh [open $report_file w]

proc gate4_log {fh message} {
    puts $message
    puts $fh $message
    flush $fh
}
proc gate4_read {path} {
    set fh [open $path r]
    set text [read $fh]
    close $fh
    return $text
}
proc gate4_collect_hdl {dir} {
    set result {}
    foreach entry [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $entry]} {
            set result [concat $result [gate4_collect_hdl $entry]]
        } elseif {[regexp -nocase {\.(v|sv|vhd|vhdl)$} [file extension $entry]]} {
            lappend result [file normalize $entry]
        }
    }
    return $result
}

set gate_status FAIL
set gate_error ""
set gate_error_info ""
set catch_rc [catch {
    doa_require_vivado_lock
    gate4_log $report_fh "VIVADO_VERSION=[version -short]"
    gate4_log $report_fh "PART=$::PART_PINNED"
    set requested_jobs [::doa_versions::env_or JOBS "8"]
    if {![string is integer -strict $requested_jobs] || $requested_jobs < 1} {
        error "JOBS must be a positive integer, got '$requested_jobs'"
    }
    set_param general.maxThreads [expr {min($requested_jobs, 8)}]
    foreach required [list $gate1_report $gate3_report $wrapper_file $xdc_file] {
        if {![file isfile $required]} { error "Required Gate-4 input is missing: $required" }
    }
    foreach {path expected label} [list \
        $gate1_report "V06 GATE1 HDL GENERATION RESULT=PASS" GATE1 \
        $gate3_report "V06 GATE3 TRANSPOSED NUMERICS RESULT=PASS" GATE3] {
        set evidence [gate4_read $path]
        if {[string first $expected $evidence] < 0} {
            error "$label evidence does not contain the required PASS marker: $path"
        }
        gate4_log $report_fh "${label}_EVIDENCE=$path"
    }
    set top_file [file join $rtl_root Channelizer_DUT.v]
    if {![file isfile $top_file]} { error "Transposed Gate-1 top is missing: $top_file" }
    set hdl_files [gate4_collect_hdl $rtl_root]
    if {[llength $hdl_files] == 0} { error "No generated HDL sources found under $rtl_root" }
    gate4_log $report_fh "GATE4 AXI WRAPPER OOC SYNTHESIS"
    gate4_log $report_fh "WRAPPER=$wrapper_file"
    gate4_log $report_fh "GENERATED_TOP=$top_file"
    gate4_log $report_fh "GENERATED_HDL_FILE_COUNT=[llength $hdl_files]"
    gate4_log $report_fh "PART=$::PART_PINNED"
    gate4_log $report_fh "CLOCK_PERIOD_NS=4.000"
    gate4_log $report_fh "READY_POLICY=direct m_axis_tready to s_axis_tready and core clk_enable"
    gate4_log $report_fh "FRAME_POLICY=TLAST on each 128th accepted output beat"

    cd $work_dir
    foreach hdl_file $hdl_files {
        switch -- [string tolower [file extension $hdl_file]] {
            ".v" { read_verilog $hdl_file }
            ".sv" { read_verilog -sv $hdl_file }
            ".vhd" { read_vhdl $hdl_file }
            ".vhdl" { read_vhdl $hdl_file }
        }
    }
    read_verilog -sv $wrapper_file
    read_xdc -mode out_of_context $xdc_file
    synth_design -top channelizer_axis_wrapper -part $::PART_PINNED \
        -mode out_of_context -flatten_hierarchy rebuilt
    write_checkpoint -force [file join $work_dir v06_gate4_axis_wrapper_ooc.dcp]
    report_utilization -file [file join $work_dir utilization.rpt]
    report_utilization -hierarchical -hierarchical_depth 4 \
        -file [file join $work_dir utilization_hierarchical.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained \
        -max_paths 20 -file [file join $work_dir timing_summary.rpt]
    report_timing -delay_type max -max_paths 20 -nworst 1 \
        -sort_by slack -file [file join $work_dir timing_paths.rpt]
    check_timing -verbose -file [file join $work_dir check_timing.rpt]
    gate4_log $report_fh "CHECKPOINT=[file join $work_dir v06_gate4_axis_wrapper_ooc.dcp]"
    gate4_log $report_fh "UTILIZATION_REPORT=[file join $work_dir utilization.rpt]"
    gate4_log $report_fh "UTILIZATION_HIERARCHICAL_REPORT=[file join $work_dir utilization_hierarchical.rpt]"
    gate4_log $report_fh "TIMING_SUMMARY_REPORT=[file join $work_dir timing_summary.rpt]"
    gate4_log $report_fh "TIMING_PATHS_REPORT=[file join $work_dir timing_paths.rpt]"
    gate4_log $report_fh "CHECK_TIMING_REPORT=[file join $work_dir check_timing.rpt]"
    gate4_log $report_fh "SYNTHESIS_COMPLETED=1"
    set gate_status PASS
} gate_error gate_error_info]
if {$catch_rc != 0} {
    gate4_log $report_fh "ERROR=$gate_error"
    gate4_log $report_fh "ERROR_INFO=$gate_error_info"
}
gate4_log $report_fh "V06 GATE4 AXI WRAPPER OOC SYNTHESIS RESULT=$gate_status"
close $report_fh
if {$catch_rc != 0} { exit 1 }
exit 0
