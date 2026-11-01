set part [expr {[info exists ::env(PART)] ? $::env(PART) : "xczu48dr-fsvg1517-2-e"}]
set period [expr {[info exists ::env(PL_CLOCK_PERIOD_NS)] ? $::env(PL_CLOCK_PERIOD_NS) : "7.8125"}]
open_project -reset beam_weight_4ch_hls
add_files src/beam_weight_4ch.cpp -cflags "-Isrc"
add_files -tb tb/beam_weight_4ch_tb.cpp -cflags "-Isrc"
set_top beam_weight_4ch
open_solution -reset solution1
set_part $part
create_clock -period $period -name default
config_export -format ip_catalog -rtl verilog -vendor openai -library doa -version 2.0 -display_name "Four-Lane Four-Channel Complex Beam Monitor"
csim_design
csynth_design
export_design
exit

