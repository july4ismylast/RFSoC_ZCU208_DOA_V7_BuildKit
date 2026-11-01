proc require_env {name} {
    if {![info exists ::env($name)] || [string trim $::env($name)] eq ""} {
        error "Required environment variable $name is empty"
    }
    return $::env($name)
}

proc open_work_project {} {
    set project [file normalize [require_env WORK_XPR]]
    if {![file exists $project]} {
        error "Working project not found: $project. Run step07_vivado_project first."
    }
    open_project $project
    set expected_part [require_env PART]
    if {[get_property PART [current_project]] ne $expected_part} {
        error "Project part [get_property PART [current_project]] does not match $expected_part"
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

