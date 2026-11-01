# Usage:
# vivado -mode batch -source create_catalog_project.tcl -tclargs <project> <ip_repo> <keyword> <part> [board_part]
set project_name [lindex $argv 0]
set ip_repo      [file normalize [lindex $argv 1]]
set keyword      [lindex $argv 2]
set part         [lindex $argv 3]
set board_part   [lindex $argv 4]
if {$project_name eq "" || $ip_repo eq "" || $keyword eq "" || $part eq ""} { error "Missing args" }
set outdir [file normalize "build/$project_name"]
file mkdir $outdir
create_project -force $project_name $outdir -part $part
if {$board_part ne ""} { catch {set_property BOARD_PART $board_part [current_project]} msg; puts "BOARD_PART: $msg" }
set_property ip_repo_paths [list $ip_repo] [current_project]
update_ip_catalog
set matches [get_ipdefs -all -filter "VLNV =~ *$keyword*"]
puts "Matching IP definitions for '$keyword': $matches"
if {[llength $matches] == 0} { error "No IP matching $keyword in $ip_repo" }
create_bd_design design_1
set vlnv [lindex $matches 0]
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
