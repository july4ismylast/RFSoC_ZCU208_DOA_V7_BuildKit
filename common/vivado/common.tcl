# common/vivado/common.tcl
# Shared helpers for every numbered Vivado stage.  Sourcing this file also
# sources config/ip_versions.tcl (the V00 version lock), so ::IPVLNV(...),
# doa_require_vivado_lock and doa_pinned_ip are available to all stages.
set ::doa_common_dir [file dirname [file normalize [info script]]]
set ::doa_root_dir [file normalize [file join $::doa_common_dir .. ..]]
source [file join $::doa_root_dir config ip_versions.tcl]

proc require_env {name} {
    if {![info exists ::env($name)] || [string trim $::env($name)] eq ""} {
        error "Required environment variable $name is empty"
    }
    return $::env($name)
}

# Append IP repository paths instead of overwriting them.  The old
# `set_property ip_repo_paths [list $ip_repo]` in step07/step08 deleted the
# base project's own repository (MTS ../../ip, PYNQ ../../ip, SAM/SPEAR
# iprepo), which breaks base-owned IP.  New paths go first (highest priority)
# and duplicates are removed.
proc doa_append_ip_repo_paths {new_paths} {
    set merged {}
    foreach path [concat $new_paths [get_property ip_repo_paths [current_project]]] {
        set norm [file normalize $path]
        if {[lsearch -exact $merged $norm] < 0} { lappend merged $norm }
    }
    set_property ip_repo_paths $merged [current_project]
    update_ip_catalog
    return $merged
}

proc open_work_project {} {
    doa_require_vivado_lock
    set project [file normalize [require_env WORK_XPR]]
    if {![file exists $project]} {
        error "Working project not found: $project. Run step07_vivado_project first."
    }
    open_project $project
    set expected_part [require_env PART]
    if {[get_property PART [current_project]] ne $expected_part} {
        error "Project part [get_property PART [current_project]] does not match $expected_part"
    }
    set board [get_property BOARD_PART [current_project]]
    if {$board ne "" && $board ne $::BOARD_PART_PINNED} {
        error "Project board part '$board' does not match pinned '$::BOARD_PART_PINNED' (config/ip_versions.tcl)"
    }
}

proc select_base_bd {} {
    set requested ""
    if {[info exists ::env(BASE_BD)]} { set requested [string trim $::env(BASE_BD)] }
    if {$requested ne ""} {
        set candidates [get_files -quiet -all */${requested}.bd]
    } else {
        set candidates [get_files -quiet -all *.bd]
    }
    if {[llength $candidates] != 1} {
        error "Expected exactly one base BD (or set BASE_BD); found: $candidates"
    }
    open_bd_design [lindex $candidates 0]
    return [current_bd_design]
}

proc ensure_output_directory {} {
    set build [file normalize [require_env BUILD]]
    set output [file join $build output]
    file mkdir $output
    return $output
}

proc require_successful_run {run_name} {
    set run [get_runs -quiet $run_name]
    if {[llength $run] != 1} { error "Vivado run $run_name does not exist" }
    set status [get_property STATUS $run]
    if {![string match "*Complete*" $status]} {
        error "Vivado run $run_name is not complete: $status"
    }
}
