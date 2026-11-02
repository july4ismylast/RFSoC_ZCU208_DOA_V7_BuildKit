set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir common.tcl]
open_work_project
set ip_repo [file normalize [require_env IP_REPO]]
# Append (never overwrite): keep any base-project IP repositories visible.
doa_append_ip_repo_paths [list $ip_repo]
select_base_bd
source [file join $script_dir create_doa_v7_hier.tcl]
if {[llength [get_bd_cells -quiet /doa_v7]]} {
    puts "Replacing existing generated hierarchy /doa_v7"
    delete_bd_objs [get_bd_cells /doa_v7]
}
set hierarchy [create_doa_v7_hier / doa_v7]
set map [file normalize [require_env ZCU208_BD_MAP]]
if {![file exists $map]} { error "ZCU208_BD_MAP not found: $map" }
source $map
set mode [expr {[info exists ::env(INTEGRATION_MODE)] ? $::env(INTEGRATION_MODE) : "mapped"}]
connect_doa_v7_to_base doa_v7 $mode
assign_bd_address
validate_bd_design
# save_bd_design persists the BD; Vivado has no "save_project" Tcl command
# (project-mode property changes persist to the .xpr automatically).
save_bd_design
puts "Integrated DOA V7 hierarchy into [current_bd_design] using mode=$mode"
close_project
