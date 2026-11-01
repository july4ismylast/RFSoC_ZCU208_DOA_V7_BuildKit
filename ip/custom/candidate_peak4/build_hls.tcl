set part [expr {[info exists ::env(PART)] ? $::env(PART) : "xczu48dr-fsvg1517-2-e"}]
set period [expr {[info exists ::env(PL_CLOCK_PERIOD_NS)] ? $::env(PL_CLOCK_PERIOD_NS) : "7.8125"}]
open_project -reset candidate_peak4_hls
add_files src/candidate_peak4.cpp -cflags "-Isrc"
add_files -tb tb/candidate_peak4_tb.cpp -cflags "-Isrc"
set_top candidate_peak4
open_solution -reset solution1
set_part $part
create_clock -period $period -name default
config_export -format ip_catalog -rtl verilog -vendor openai -library doa -version 1.0 -display_name "Four-Lane Spectrum Candidate Peak"
csim_design
csynth_design
export_design
exit

