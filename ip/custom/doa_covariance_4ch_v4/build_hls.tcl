set part [expr {[info exists ::env(PART)] ? $::env(PART) : "xczu48dr-fsvg1517-2-e"}]
set period [expr {[info exists ::env(PL_CLOCK_PERIOD_NS)] ? $::env(PL_CLOCK_PERIOD_NS) : "7.8125"}]
open_project -reset doa_covariance_4ch_v4_prj
set_top doa_covariance_4ch_v4
add_files src/doa_covariance_4ch_v4.cpp -cflags "-Isrc"
add_files -tb tb/doa_covariance_4ch_v4_tb.cpp -cflags "-Isrc"
open_solution -reset solution1
set_part $part
create_clock -period $period -name default
config_export -format ip_catalog -rtl verilog -vendor openai -library doa -version 7.0 -display_name "DOA V7 Four-Lane Covariance"
csim_design
csynth_design
export_design
exit

