# V06 Gate-4 OOC constraints only. Not for the integrated ZCU208 BD.
create_clock -name v06_gate4_clk -period 4.000 -waveform {0.000 2.000} [get_ports aclk]
set_false_path -from [get_ports aresetn]
set_input_delay -clock [get_clocks v06_gate4_clk] 0.000 \
    [get_ports {s_axis_tdata[*] s_axis_tvalid m_axis_tready}]
set_output_delay -clock [get_clocks v06_gate4_clk] 0.000 \
    [get_ports {s_axis_tready m_axis_tdata[*] m_axis_tvalid m_axis_tlast}]
