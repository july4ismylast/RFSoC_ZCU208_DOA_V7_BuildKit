# V06 Gate 4B: behavioral handshake/framing check of the isolated wrapper.
# Uses the exact passed Gate-1T RTL; does not package IP or change any BD.
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir .. .. ..]]
source [file join $root_dir config ip_versions.tcl]
set report_file [file join $::env(BUILD) output v06_gate4_axis_wrapper_sim.rpt]
set work_dir [file join $::env(BUILD) v06_gate4_axis_wrapper_sim]
set gate1_report [file join $::env(BUILD) output v06_gate1_hdl_generation_transposed.rpt]
set gate3_report [file join $::env(BUILD) output v06_gate3_transposed_numerics.rpt]
set gate4_report [file join $::env(BUILD) output v06_gate4_axis_wrapper_ooc.rpt]
set rtl_root [file join $script_dir hdl_prj hdlsrc_transposed zu48dr_channelizer_ip]
set wrapper_file [file join $script_dir channelizer_axis_wrapper.sv]
set testbench_file [file join $script_dir tb_channelizer_axis_wrapper.sv]
file mkdir [file dirname $report_file]
file mkdir $work_dir
set report_fh [open $report_file w]

proc gate4sim_log {fh message} {
    puts $message
    puts $fh $message
    flush $fh
}
proc gate4sim_read {path} {
    set fh [open $path r]
    set text [read $fh]
    close $fh
    return $text
}
proc gate4sim_collect_hdl {dir} {
    set result {}
    foreach entry [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $entry]} {
            set result [concat $result [gate4sim_collect_hdl $entry]]
        } elseif {[regexp -nocase {\.(v|sv|vhd|vhdl)$} [file extension $entry]]} {
            lappend result [file normalize $entry]
        }
    }
    return [lsort -unique $result]
}

set gate_status FAIL
set gate_error ""
set gate_error_info ""
set catch_rc [catch {
    doa_require_vivado_lock
    gate4sim_log $report_fh "VIVADO_VERSION=[version -short]"
    gate4sim_log $report_fh "PART=$::PART_PINNED"
    foreach required [list $gate1_report $gate3_report $gate4_report $wrapper_file $testbench_file] {
        if {![file isfile $required]} { error "Required Gate-4B input is missing: $required" }
    }
    foreach {path expected label} [list \
        $gate1_report "V06 GATE1 HDL GENERATION RESULT=PASS" GATE1 \
        $gate3_report "V06 GATE3 TRANSPOSED NUMERICS RESULT=PASS" GATE3 \
        $gate4_report "V06 GATE4 AXI WRAPPER OOC SYNTHESIS RESULT=PASS" GATE4_OOC] {
        set evidence [gate4sim_read $path]
        if {[string first $expected $evidence] < 0} {
            error "$label evidence does not contain the required PASS marker: $path"
        }
        gate4sim_log $report_fh "${label}_EVIDENCE=$path"
    }
    set top_file [file join $rtl_root Channelizer_DUT.v]
    if {![file isfile $top_file]} { error "Transposed Gate-1 top is missing: $top_file" }
    set hdl_files [gate4sim_collect_hdl $rtl_root]
    set verilog_files {}
    set systemverilog_files {}
    set vhdl_files {}
    foreach hdl_file $hdl_files {
        switch -- [string tolower [file extension $hdl_file]] {
            ".v" { lappend verilog_files $hdl_file }
            ".sv" { lappend systemverilog_files $hdl_file }
            ".vhd" { lappend vhdl_files $hdl_file }
            ".vhdl" { lappend vhdl_files $hdl_file }
        }
    }
    if {[llength $verilog_files] + [llength $systemverilog_files] + [llength $vhdl_files] == 0} {
        error "No Gate-1 HDL sources found under $rtl_root"
    }
    gate4sim_log $report_fh "GENERATED_HDL_FILE_COUNT=[llength $hdl_files]"
    gate4sim_log $report_fh "TESTBENCH=$testbench_file"
    gate4sim_log $report_fh "TEST_PLAN=128 input SSR beats; force 8-cycle downstream stall; check stable output, upstream ready, and TLAST at accepted output beat 128"

    cd $work_dir
    if {[llength $verilog_files] > 0} {
        exec xvlog -work work {*}$verilog_files >@stdout 2>@1
    }
    if {[llength $systemverilog_files] > 0} {
        exec xvlog -sv -work work {*}$systemverilog_files >@stdout 2>@1
    }
    if {[llength $vhdl_files] > 0} {
        exec xvhdl -work work {*}$vhdl_files >@stdout 2>@1
    }
    exec xvlog -sv -work work $wrapper_file $testbench_file >@stdout 2>@1
    gate4sim_log $report_fh "XVLOG_COMPLETED=1"

    # The testbench declares 1 ns / 1 ps while generated Gate-1 modules do
    # not carry a `timescale directive. Supply a default at elaboration so
    # mixed source files are legal and all delays are deterministic.
    exec xelab -debug typical -timescale 1ns/1ps \
        -L unisims_ver -L unimacro_ver -L secureip \
        -s v06_gate4_axis_wrapper_sim_snapshot work.tb_channelizer_axis_wrapper \
        >@stdout 2>@1
    gate4sim_log $report_fh "XELAB_COMPLETED=1"

    set sim_log [file join $work_dir xsim.log]
    exec xsim v06_gate4_axis_wrapper_sim_snapshot -runall -log $sim_log \
        >@stdout 2>@1
    if {![file isfile $sim_log]} { error "XSim log was not created: $sim_log" }
    set sim_text [gate4sim_read $sim_log]
    if {[string first "GATE4 AXI WRAPPER SIM RESULT=PASS" $sim_text] < 0} {
        error "XSim completed without the testbench PASS marker; see $sim_log"
    }
    gate4sim_log $report_fh "XSIM_LOG=$sim_log"
    gate4sim_log $report_fh "SIMULATION_COMPLETED=1"
    set gate_status PASS
} gate_error gate_error_info]
if {$catch_rc != 0} {
    gate4sim_log $report_fh "ERROR=$gate_error"
    gate4sim_log $report_fh "ERROR_INFO=$gate_error_info"
}
gate4sim_log $report_fh "V06 GATE4 AXI WRAPPER SIM RESULT=$gate_status"
close $report_fh
if {$catch_rc != 0} { exit 1 }
exit 0
