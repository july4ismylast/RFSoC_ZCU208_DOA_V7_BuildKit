# Stage V03 gates 2 + 4 (read-only audit of the built, unmodified MTS base):
#
#   * open the V03 base project (BASE_XPR; default = the stage-V03 output)
#   * verify Vivado 2023.2, part and board part against the lock
#   * report_ip_status          -> build/output/v03_mts_report_ip_status.rpt
#   * validate_bd_design on the base BD (BASE_BD, default "mts")
#   * write_bd_tcl               -> build/output/v03_mts_base_bd.tcl
#
# The base project is never saved by this script.  Run from the repo root:
#   vivado -mode batch -source common/vivado/v03_report_mts_base.tcl
# Optional env overrides: BASE_XPR, BASE_BD, BUILD, PART, BOARD_PART.
# Gate 2 still needs a human read of the IP-status report: no IP may be
# Locked/Outdated (grep it).  Only then is step07 allowed to consume the base.

set running [version -short]
if {[string first "2023.2" $running] == -1} {
    error "V03 audit: this flow is locked to Vivado 2023.2, running $running"
}

proc env_or {name default_value} {
    if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
        return [string trim $::env($name)]
    }
    return $default_value
}

set _script_dir [file dirname [file normalize [info script]]]
set _repo_root [file normalize [file join $_script_dir .. ..]]
set build_root [file normalize [env_or BUILD [file join $_repo_root build]]]
set base_xpr [file normalize [env_or BASE_XPR \
    [file join $build_root mts_base_src_2023p2 boards ZCU208 build_mts mts mts.xpr]]]
set base_bd [env_or BASE_BD "mts"]
set expected_part [env_or PART "xczu48dr-fsvg1517-2-e"]
set expected_board [env_or BOARD_PART "xilinx.com:zcu208:part0:2.0"]
set out_dir [file join $build_root output]
file mkdir $out_dir

if {![file exists $base_xpr]} {
    error "V03 audit: base project not found: $base_xpr\nBuild stage V03 first (see V03_MTS_BASE_2023P2.md): prepare script, then 'make' in boards/ZCU208/build_mts."
}

open_project $base_xpr
set part [get_property PART [current_project]]
set board [get_property BOARD_PART [current_project]]
puts "V03 BASE: project=$base_xpr"
puts "V03 BASE: PART=$part BOARD_PART=$board"
if {$part ne $expected_part} {
    error "V03 audit: base part '$part' != locked '$expected_part'"
}
if {$board ne "" && $board ne $expected_board} {
    error "V03 audit: base board part '$board' != locked '$expected_board'"
}

set ip_status_rpt [file join $out_dir "v03_mts_report_ip_status.rpt"]
report_ip_status -file $ip_status_rpt
puts "V03 BASE: wrote $ip_status_rpt (gate 2: check it for Locked/Outdated IP)"

set bd_candidates [get_files -quiet -all */${base_bd}.bd]
if {[llength $bd_candidates] != 1} {
    set bd_candidates [get_files -quiet -all *.bd]
}
if {[llength $bd_candidates] != 1} {
    error "V03 audit: expected exactly one base BD matching '${base_bd}.bd'; found: $bd_candidates"
}
open_bd_design [lindex $bd_candidates 0]
validate_bd_design
puts "V03 BASE: validate_bd_design completed for [current_bd_design]"

set bd_tcl [file join $out_dir "v03_mts_base_bd.tcl"]
write_bd_tcl -force $bd_tcl
puts "V03 BASE: wrote $bd_tcl (gate 4: reviewable 2022.1.2 -> 2023.2 BD export)"

close_project
puts "V03 BASE AUDIT: PASS (part/board verified; reports in $out_dir)"
