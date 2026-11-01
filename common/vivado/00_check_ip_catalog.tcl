# common/vivado/00_check_ip_catalog.tcl
# -----------------------------------------------------------------------------
# Stage V00 proof step: ask the *installed* Vivado for every AMD catalog VLNV
# pinned in config/ip_versions.tcl and write build/output/ip_catalog_lock.txt.
#
# Run via `make step00_preflight` (scripts/preflight.sh invokes this at the
# end).  It uses an in-memory project so it never touches BASE_XPR / WORK_XPR.
# Custom project IP (covariance, spectrum, ...) is intentionally NOT checked
# here: it is checked by scripts/collect_ip.sh at step06 and by doa_pinned_ip
# at step08, after build/ip_repo exists.
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir common.tcl]
doa_require_vivado_lock

set build_dir [expr {[info exists ::env(BUILD)] && [string trim $::env(BUILD)] ne "" \
    ? [file normalize $::env(BUILD)] \
    : [file normalize [file join $script_dir .. .. build]]}]
set output_dir [file join $build_dir output]
file mkdir $output_dir
set report_file [file join $output_dir ip_catalog_lock.txt]

create_project -in_memory -part $::PART_PINNED
if {[catch {set_property BOARD_PART $::BOARD_PART_PINNED [current_project]} msg]} {
    puts "WARNING: could not set BOARD_PART $::BOARD_PART_PINNED in-memory: $msg"
    puts "         (board files are re-checked for real at step07)"
}
update_ip_catalog

set report [open $report_file w]
puts $report "# DOA V7 IP catalog lock proof"
puts $report "# vivado=[version -short] lock=$::VIVADO_LOCK_VERSION part=$::PART_PINNED board=$::BOARD_PART_PINNED base_kind=$::BASE_KIND_PINNED"
puts $report "# key\tpinned_vlnv\tstatus"

set failures 0
foreach key $::IP_CATALOG_KEYS {
    set vlnv $::IPVLNV($key)
    set defs [get_ipdefs -all -filter "VLNV == $vlnv"]
    if {[llength $defs] == 1} {
        puts $report "$key\t$vlnv\tPASS"
        puts "PASS catalog $key  $vlnv"
    } else {
        set ip_name [lindex [split $vlnv :] 2]
        set available [get_ipdefs -all -filter "NAME == $ip_name"]
        puts $report "$key\t$vlnv\tFAIL available=$available"
        puts "FAIL catalog $key  pinned=$vlnv  available=$available"
        incr failures
    }
}
foreach key $::IP_CUSTOM_KEYS {
    puts $report "$key\t$::IPVLNV($key)\tDEFERRED (checked at step06/step08)"
}
close $report
close_project

if {$failures} {
    error "$failures pinned catalog IP(s) missing in Vivado [version -short]. \
See $report_file and fix the VLNV line(s) in config/ip_versions.tcl."
}
puts "IP catalog lock proof written: $report_file"
