# Repair only the isolated working project's MTS RTL module references.
source [file join [file dirname [file normalize [info script]]] common.tcl]
open_work_project
set output [ensure_output_directory]
set rtl [file join [file normalize [require_env BUILD]] mts_base_src_2023p2 boards ip rtl]
# Check both exact upstream inputs before making any project changes.
foreach name {ADCRAMcapture DACRAMstreamer} {
    set path [file join $rtl ${name}.v]
    if {![file isfile $path]} { error "Required pinned MTS RTL missing: $path" }
}
select_base_bd
set bd [get_files -quiet -all */[current_bd_design].bd]
if {[llength $bd] != 1} { error "Expected one working BD: $bd" }
# Keep a timestamped backup before refreshing the module references.
file copy [lindex $bd 0] [file join $output mts_before_module_refresh_[clock seconds].bd]
foreach name {ADCRAMcapture DACRAMstreamer} {
    set path [file normalize [file join $rtl ${name}.v]]
    if {[llength [get_files -quiet $path]] == 0} {
        add_files -norecurse -fileset sources_1 $path
    }
    set_property USED_IN_SYNTHESIS true [get_files $path]
    set_property USED_IN_SIMULATION true [get_files $path]
}
update_compile_order -fileset sources_1
# Vivado 2023.2 help specifies IP instances from get_ips, NOT BD cells.
# Resolve the exact five instance names recorded by report_ip_status first.
set refs {}
foreach name {
    mts_ADCRAMcapture_0_0 mts_ADCRAMcapture_0_1
    mts_ADCRAMcapture_0_2 mts_ADCRAMcapture_0_3
    mts_DACRAMstreamer_0_0
} {
    set ip [get_ips -quiet $name]
    if {[llength $ip] != 1} {
        error "Expected exactly one module-reference IP $name; found: $ip"
    }
    lappend refs [lindex $ip 0]
}
foreach ip $refs {
    puts "Refreshing MTS module-reference IP: $ip"
    # Do not use -quiet: failures must stop the repair and remain visible.
    puts [update_module_reference -verbose $ip]
}
set count [llength $refs]
validate_bd_design
save_bd_design
report_ip_status -file [file join $output opfb_work_project_ip_status_after_repair.rpt]
puts "Refreshed $count MTS module references in isolated working project; no IP version upgrades performed."
close_project
