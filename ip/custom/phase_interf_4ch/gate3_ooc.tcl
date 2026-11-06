# ip/custom/phase_interf_4ch/gate3_ooc.tcl
# -----------------------------------------------------------------------------
# V07 Gate 3: out-of-context synthesis + timing of the *packaged*
# phase_interf_4ch IP, at the 250 MHz wideband fabric clock
# (WIDEBAND_CLOCK_PERIOD_NS = 4.0 ns, config.mk).
#
# Written to the same shape as ip/matlab/channelizer_hdl/v06_gate2_ooc_synth.tcl:
# a key=value summary report plus the raw Vivado reports, so a gate can be
# quoted (or refuted) from a single file.
#
# STATUS: NOT RUN.  No Vivado exists in the authoring environment, so this
# script has never been executed; V07 section 8 lists G3 as NOT RUN.  If a
# command below misbehaves on 2023.2, the fix is local to this file and the
# report keys it promises -- do not weaken the gate by deleting it.
#
# Prerequisites (both are real gates themselves):
#   1. make step05_hls_phase_interf   -> Vitis HLS csim + csynth + export_design
#   2. make step06_collect_ip         -> $IP_REPO/phase_interf_4ch/component.xml
#
# Run:
#   make -C ip/custom/phase_interf_4ch gate3-ooc
# which is:
#   vivado -mode batch -nojournal -nolog -source gate3_ooc.tcl
#
# Writes build/output/v07_gate3_*.rpt and build/v07_gate3_ooc/.
# -----------------------------------------------------------------------------

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir .. .. .. common vivado common.tcl]
# common.tcl sources config/ip_versions.tcl, so ::PART_PINNED, ::BOARD_PART_PINNED,
# ::IPVLNV(phase_interf) and doa_require_vivado_lock are available.

proc log_line {fh message} {
    puts $message
    puts $fh $message
    flush $fh
}

# Read "Used | ..." for a utilisation-table row, tolerating a footnote asterisk.
proc parse_utilization_used {text label} {
    foreach raw_line [split $text "\n"] {
        set line [string trimright $raw_line "\r"]
        if {[string first "|" $line] < 0} { continue }
        set cells {}
        foreach cell [split $line "|"] {
            set cell [string trim $cell]
            if {$cell ne ""} { lappend cells $cell }
        }
        if {[llength $cells] < 2} { continue }
        set row_label [string trimright [lindex $cells 0] "* "]
        if {$row_label eq $label} { return [lindex $cells 1] }
    }
    return ""
}

# First WNS row of a report_timing_summary table.
proc parse_timing_summary {text} {
    set lines [split $text "\n"]
    set count [llength $lines]
    for {set i 0} {$i < $count} {incr i} {
        if {[string first "WNS(ns)" [lindex $lines $i]] < 0} { continue }
        for {set j [expr {$i + 1}]} {$j < $count} {incr j} {
            set fields [regexp -all -inline {\S+} [string trim [lindex $lines $j]]]
            if {[llength $fields] < 8} { continue }
            set first [lindex $fields 0]
            if {[string is double -strict $first] || [string equal -nocase $first "inf"]} {
                return $fields
            }
        }
    }
    return {}
}

proc read_text_file {path} {
    set fh [open $path r]
    set data [read $fh]
    close $fh
    return $data
}

doa_require_vivado_lock

set build_dir [expr {[info exists ::env(BUILD)] && [string trim $::env(BUILD)] ne "" \
    ? [file normalize $::env(BUILD)] \
    : [file normalize [file join $script_dir .. .. .. build]]}]
set ip_repo [expr {[info exists ::env(IP_REPO)] && [string trim $::env(IP_REPO)] ne "" \
    ? [file normalize $::env(IP_REPO)] \
    : [file join $build_dir ip_repo]}]
set output_dir [file join $build_dir output]
set work_dir [file join $build_dir v07_gate3_ooc]
file mkdir $output_dir
file mkdir $work_dir

set summary_file [file join $output_dir v07_gate3_ooc_synthesis.rpt]
set utilization_file [file join $output_dir v07_gate3_utilization.rpt]
set utilization_hier_file [file join $output_dir v07_gate3_utilization_hierarchical.rpt]
set timing_summary_file [file join $output_dir v07_gate3_timing_summary.rpt]
set timing_paths_file [file join $output_dir v07_gate3_timing_paths.rpt]
set clocks_file [file join $output_dir v07_gate3_clocks.rpt]
set check_timing_file [file join $output_dir v07_gate3_check_timing.rpt]

# -----------------------------------------------------------------------------
# 0. Prerequisites: the packaged IP must exist with the pinned VLNV.
# -----------------------------------------------------------------------------
set component_xml [file join $ip_repo phase_interf_4ch component.xml]
if {![file exists $component_xml]} {
    error "Missing packaged IP $component_xml. Run 'make step05_hls_phase_interf' \
           (Vitis HLS 2023.2) and then 'make step06_collect_ip' first. Gate 3 \
           measures the IP that step05/step06 actually produced; it does not \
           synthesise the sources directly."
}

# -----------------------------------------------------------------------------
# 1. In-memory project on the pinned part, catalog the repo, pin the VLNV.
# -----------------------------------------------------------------------------
create_project -in_memory -part $::PART_PINNED
doa_append_ip_repo_paths [list $ip_repo]

set expected_vlnv $::IPVLNV(phase_interf)
set defs [get_ipdefs -all -filter "VLNV == $expected_vlnv"]
if {[llength $defs] != 1} {
    set found [get_ipdefs -all -filter "NAME == phase_interf_4ch"]
    error "IP repo $ip_repo does not contain the pinned VLNV $expected_vlnv \
           (found: $found). Do not 'fix' this by changing IPVER_PHASE_INTERF \
           unless config.mk and config/ip_versions.tcl change together."
}
set ip_name phase_interf_4ch_ooc
create_ip -vlnv $expected_vlnv -module_name $ip_name

# The clock is the IP's own constraint, exported by Vitis HLS from
# WIDEBAND_CLOCK_PERIOD_NS (4.0 ns).  Record what config.mk asked for so a
# mismatch between the script and the packaged XDC is visible in the report.
set expected_period ""
if {[info exists ::env(WIDEBAND_CLOCK_PERIOD_NS)]} {
    set expected_period [string trim $::env(WIDEBAND_CLOCK_PERIOD_NS)]
}

# -----------------------------------------------------------------------------
# 2. Out-of-context synthesis + reports.
# -----------------------------------------------------------------------------
synth_ip [get_ips $ip_name]

# Report commands need an open design.  For an OOC IP run that is
# `open_run <ip>`, which loads the synthesized checkpoint of that run.
if {[catch {open_run [get_ips $ip_name]} open_msg]} {
    error "Gate 3: could not open the synthesized IP design ($open_msg). \
           If 'open_run <ip>' is not accepted by this Vivado, open the run \
           checkpoint directly: set dcp [get_property DIRECTORY \
           [get_runs ${ip_name}_synth_1]], then open_checkpoint \$dcp/<name>.dcp"
}

set summary_fh [open $summary_file w]
log_line $summary_fh "# V07 Gate 3: packaged phase_interf_4ch, out-of-context synthesis and timing"
log_line $summary_fh "# vivado=[version -short] part=$::PART_PINNED board=$::BOARD_PART_PINNED"
log_line $summary_fh "# vlnv=$expected_vlnv"
log_line $summary_fh "# expected_clock_period_ns=$expected_period (config.mk WIDEBAND_CLOCK_PERIOD_NS, exported by Vitis HLS)"

report_utilization -file $utilization_file
report_utilization -hierarchical -file $utilization_hier_file
report_timing_summary -delay_type max -file $timing_summary_file
report_timing -delay_type max -max_paths 10 -nworst 1 -file $timing_paths_file
report_clocks -file $clocks_file
check_timing -verbose -file $check_timing_file

set utilization_text [read_text_file $utilization_file]
set timing_text [read_text_file $timing_summary_file]
set clocks_text [read_text_file $clocks_file]

set lut [parse_utilization_used $utilization_text "CLB LUTs"]
set ff [parse_utilization_used $utilization_text "CLB Registers"]
set dsp [parse_utilization_used $utilization_text "DSPs"]
set bram [parse_utilization_used $utilization_text "Block RAM Tile"]
set timing [parse_timing_summary $timing_text]

set wns ""
set tns ""
if {[llength $timing] >= 8} {
    set wns [lindex $timing 0]
    set tns [lindex $timing 1]
}

# The IP XDC clock must be the 4.0 ns wideband period.  Report it, and fail if
# the exported constraint is the 7.8125 ns PL clock -- that would mean the IP
# was packaged for the wrong domain and every timing number here is meaningless.
# Ask the design for the clock period directly instead of parsing the report
# text: a regex with a brace class inside a braced word is not valid Tcl
# (braces are counted even inside {..}), and a silently empty period would
# make the check below pass for the wrong reason.
set clock_period ""
if {[catch {
    foreach clk [get_clocks -quiet] {
        if {[string first "ap_clk" [get_property NAME $clk]] >= 0} {
            set clock_period [get_property PERIOD $clk]
        }
    }
} clock_msg]} {
    log_line $summary_fh "V07_GATE3_CLOCK_QUERY_WARNING=$clock_msg"
}
if {$clock_period eq ""} {
    log_line $summary_fh "V07_GATE3_CLOCK_QUERY_WARNING=no ap_clk found in [get_clocks -quiet] (see $clocks_file)"
}

log_line $summary_fh "V07_GATE3_OOC_LUT=$lut"
log_line $summary_fh "V07_GATE3_OOC_FF=$ff"
log_line $summary_fh "V07_GATE3_OOC_DSP=$dsp"
log_line $summary_fh "V07_GATE3_OOC_BRAM=$bram"
log_line $summary_fh "V07_GATE3_OOC_WNS_NS=$wns"
log_line $summary_fh "V07_GATE3_OOC_TNS_NS=$tns"
log_line $summary_fh "V07_GATE3_OOC_CLOCK_PERIOD_NS=$clock_period"
log_line $summary_fh "V07_GATE3_OOC_STATUS=SYNTHESISED"

if {$clock_period ne "" && $expected_period ne "" && \
    [expr {abs($clock_period - $expected_period) > 0.01}]} {
    log_line $summary_fh "V07_GATE3_RESULT=FAIL clock period $clock_period ns != $expected_period ns"
    close $summary_fh
    error "Gate 3: ap_clk period $clock_period ns does not match config.mk \
           WIDEBAND_CLOCK_PERIOD_NS=$expected_period ns. The IP was packaged in \
           the wrong clock domain; rebuild with build_hls.tcl (which uses \
           WIDEBAND_CLOCK_PERIOD_NS, not PL_CLOCK_PERIOD_NS)."
}
if {$wns eq ""} {
    log_line $summary_fh "V07_GATE3_RESULT=INCONCLUSIVE no WNS row parsed from $timing_summary_file"
    close $summary_fh
    error "Gate 3: could not parse WNS from $timing_summary_file"
}
if {[expr {$wns < 0.0}]} {
    log_line $summary_fh "V07_GATE3_RESULT=FAIL timing not met, WNS=$wns ns"
    close $summary_fh
    error "Gate 3: timing not met at $expected_period ns (WNS=$wns ns). \
           See $timing_paths_file. Reduce the CORDIC pair count per cycle or \
           split the phase pass; do not raise the clock period."
}
log_line $summary_fh "V07_GATE3_RESULT=PASS WNS=$wns ns"
close $summary_fh

puts "V07 Gate 3 complete: $summary_file"
puts "  LUT=$lut FF=$ff DSP=$dsp BRAM=$bram WNS=${wns}ns TNS=${tns}ns clock=$clock_period ns"
