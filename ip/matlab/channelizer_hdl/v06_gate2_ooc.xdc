# V06 Gate-2 one-channel out-of-context constraints.
#
# This file is only for the standalone Channelizer_DUT OOC synthesis in
# v06_gate2_ooc_synth.tcl.  It must not be copied into the production
# ZCU208 block design: there the 250 MHz ADC AXI-Stream clock, the local
# reset synchronizer and the boundary registers provide the real context.
#
# The 4.000 ns period is config.mk WIDEBAND_CLOCK_PERIOD_NS.  The Gate-2
# Tcl checks that environment value before reading this file.  Zero
# input/output delays intentionally allocate the full clock period to
# the generated module for this internal-feasibility gate; integrated
# source/destination routing is a later V07 timing task.

create_clock -name v06_wideband_clk -period 4.000 -waveform {0.000 2.000} [get_ports clk]

# The production wrapper will tie the HDL Coder clock enable high for
# continuous 250 MHz operation.  Reset assertion/deassertion will be
# handled by the production reset context and is not a datapath timing
# path for this OOC gate.
set_case_analysis 1 [get_ports clk_enable]
set_false_path -from [get_ports reset]

set_input_delay -clock [get_clocks v06_wideband_clk] 0.000 [get_ports {dataIn_re_* dataIn_im_* validIn}]
set_output_delay -clock [get_clocks v06_wideband_clk] 0.000 [get_ports {ce_out dataOut_re_* dataOut_im_* validOut}]
