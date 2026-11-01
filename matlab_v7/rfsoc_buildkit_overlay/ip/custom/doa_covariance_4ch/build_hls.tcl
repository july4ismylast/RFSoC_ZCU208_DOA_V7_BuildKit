set part [expr {[info exists ::env(PART)] ? $::env(PART) : "xczu48dr-fsvg1517-2-e"}]
open_project -reset doa_covariance_4ch_hls
add_files src/doa_covariance_4ch.cpp
set_top doa_covariance_4ch
open_solution -reset solution1
set_part $part
create_clock -period 4.0 -name default
config_export -format ip_catalog -vendor ttr -library doa -version 1.0 -display_name "4CH Calibrated DOA Covariance"
csynth_design
export_design
exit
