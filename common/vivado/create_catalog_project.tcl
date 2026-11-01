# Dev/inspection tool only (used by ip/upstream_opfb adapters): build a
# throwaway project containing exactly one packaged IP so its interfaces can
# be inspected.  NOT part of the production stage flow.
#
# Usage:
# vivado -mode batch -source create_catalog_project.tcl -tclargs <project> <ip_repo> <full-VLNV-or-unique-NAME> <part> [board_part]
#
# Version rule: a full VLNV argument must exist exactly once.  A bare NAME is
# accepted for the legacy OPFB adapters, but still must resolve to exactly one
# IP definition; if it resolves to 0 or >1 this script fails and lists what is
# available (the old "first substring match" behaviour was removed).  Whatever
# VLNV wins inspection must be pinned in config/ip_versions.tcl before any
# production use.
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir common.tcl]
doa_require_vivado_lock

set project_name [lindex $argv 0]
set ip_repo      [file normalize [lindex $argv 1]]
set keyword      [lindex $argv 2]
set part         [lindex $argv 3]
set board_part   [lindex $argv 4]
if {$project_name eq "" || $ip_repo eq "" || $keyword eq "" || $part eq ""} { error "Missing args" }
if {$board_part eq ""} { set board_part $::BOARD_PART_PINNED }
set outdir [file normalize "build/$project_name"]
file mkdir $outdir
create_project -force $project_name $outdir -part $part
set_property BOARD_PART $board_part [current_project]
doa_append_ip_repo_paths [list $ip_repo]

if {[string match "*:*" $keyword]} {
    set matches [get_ipdefs -all -filter "VLNV == $keyword"]
} else {
    set matches [get_ipdefs -all -filter "NAME == $keyword"]
    if {[llength $matches] == 0} {
        set matches [get_ipdefs -all -filter "VLNV =~ *$keyword*"]
        puts "NOTE: '$keyword' is not an exact IP NAME; substring matches are inspection-only."
    }
}
puts "Matching IP definitions for '$keyword': $matches"
if {[llength $matches] != 1} {
    error "Need exactly one IP matching '$keyword' in $ip_repo, found [llength $matches]: $matches. Pass the full pinned VLNV instead."
}
create_bd_design design_1
set vlnv [lindex $matches 0]
puts "Inspecting pinned VLNV: $vlnv"
create_bd_cell -type ip -vlnv $vlnv dut
# Make all interfaces/pins external where possible so this is a standalone inspection project.
foreach intf [get_bd_intf_pins -of_objects [get_bd_cells dut]] { catch {make_bd_intf_pins_external $intf} }
foreach pin [get_bd_pins -of_objects [get_bd_cells dut]] {
    set dir [get_property DIR $pin]
    if {$dir eq "I" || $dir eq "O" || $dir eq "IO"} { catch {make_bd_pins_external $pin} }
}
validate_bd_design -force
save_bd_design
puts "Created catalog project $project_name with $vlnv"
