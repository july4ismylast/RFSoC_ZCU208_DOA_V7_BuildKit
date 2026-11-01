open_project -reset doa_covariance_4ch_v4_prj
set_top doa_covariance_4ch_v4
add_files src/doa_covariance_4ch_v4.cpp
add_files -tb tb/doa_covariance_4ch_v4_tb.cpp -cflags "-Isrc"
open_solution -reset solution1
set_part {xczu48dr-fsvg1517-2-e}
create_clock -period 7.8125 -name default
config_export -format ip_catalog -rtl verilog
csim_design
csynth_design
export_design
exit
