source [file join [file dirname [file normalize [info script]]] common.tcl]
doa_require_vivado_lock
# BASE_XPR is the one input this stage cannot invent: it must be a verified
# ZCU208 base project.  For the locked base (BASE_KIND=mts, the default)
# config.mk already points BASE_XPR at the stage-V03 output, so an empty or
# missing value here means V03 has not been run yet -- say exactly that
# instead of a bare "environment variable is empty".
if {![info exists ::env(BASE_XPR)] || [string trim $::env(BASE_XPR)] eq ""} {
    error "BASE_XPR is empty.\nFor the locked MTS base, run stage V03 first (see V03_MTS_BASE_2023P2.md):\n  make step01_fetch_references FETCH_SET=RFSoC-MTS\n  ./scripts/prepare_mts_2023p2_patch.sh\n  cd build/mts_base_src_2023p2/boards/ZCU208/build_mts && vivado -mode batch -source mts.tcl\nThat creates .../build_mts/mts/mts.xpr, which config.mk then uses by default (BASE_KIND=mts).\nOr set BASE_XPR=/absolute/path/to/a/verified_ZCU208_project.xpr explicitly."
}
set base [file normalize $::env(BASE_XPR)]
set work [file normalize [require_env WORK_XPR]]
set project_name [require_env PROJECT_NAME]
set ip_repo [file normalize [require_env IP_REPO]]
if {![file exists $base]} {
    error "BASE_XPR not found: $base\nFor BASE_KIND=mts this file is the stage-V03 output. Build the unmodified MTS base first (see V03_MTS_BASE_2023P2.md):\n  make step01_fetch_references FETCH_SET=RFSoC-MTS\n  ./scripts/prepare_mts_2023p2_patch.sh\n  cd build/mts_base_src_2023p2/boards/ZCU208/build_mts && vivado -mode batch -source mts.tcl\nThen re-run: make step07_vivado_project"
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
set _base_board [get_property BOARD_PART [current_project]]
if {$_base_board ne "" && $_base_board ne $::BOARD_PART_PINNED} {
    error "BASE_XPR board part '$_base_board' does not match pinned '$::BOARD_PART_PINNED' (config/ip_versions.tcl)"
}
save_project_as -force $project_name $work_dir
# Append (never overwrite): the verified base may carry its own IP repo(s).
doa_append_ip_repo_paths [list $ip_repo]
# NOTE: there is no "save_project" Tcl command in Vivado (proved on the
# 2023.2 PC: it errors asking for save_project_as usage).  In project mode,
# property changes such as ip_repo_paths persist to the .xpr automatically;
# block-design edits are persisted with save_bd_design instead.  Prove the
# copy is complete by reopening it exactly as step08 will.
close_project
open_project $work
if {[get_property PART [current_project]] ne [require_env PART]} {
    error "Work project part [get_property PART [current_project]] does not match [require_env PART]"
}
set _work_board [get_property BOARD_PART [current_project]]
if {$_work_board ne "" && $_work_board ne $::BOARD_PART_PINNED} {
    error "Work project board part '$_work_board' does not match pinned '$::BOARD_PART_PINNED'"
}
set _work_repos [get_property ip_repo_paths [current_project]]
if {[lsearch -exact $_work_repos $ip_repo] < 0} {
    error "Work project ip_repo_paths does not contain $ip_repo (found: $_work_repos)"
}
puts "Created + verified isolated ZCU208 project: $work"
puts "Work project ip_repo_paths: $_work_repos"
close_project

