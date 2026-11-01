source [file join [file dirname [file normalize [info script]]] common.tcl]
set base [file normalize [require_env BASE_XPR]]
set work [file normalize [require_env WORK_XPR]]
set project_name [require_env PROJECT_NAME]
set ip_repo [file normalize [require_env IP_REPO]]
if {![file exists $base]} {
    error "BASE_XPR not found: $base. Supply a verified ZCU208 RFDC/MTS project."
}
if {![file exists [file join $ip_repo ip_manifest.tsv]]} {
    error "IP manifest missing. Run step06_collect_ip before copying the project."
}
set work_dir [file dirname $work]
file mkdir $work_dir
open_project $base
if {[get_property PART [current_project]] ne [require_env PART]} {
    error "BASE_XPR targets [get_property PART [current_project]], not [require_env PART]"
}
save_project_as -force $project_name $work_dir
set_property ip_repo_paths [list $ip_repo] [current_project]
update_ip_catalog
save_project
puts "Created isolated ZCU208 project: $work"
close_project

