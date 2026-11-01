# All IP below is instantiated ONLY through doa_create_pinned_ip, i.e. by the
# exact VLNV variables in config/ip_versions.tcl (V00 version lock).  The old
# find_unique_ipdef (last sorted NAME match, version ignored) and the
# xilinx.com:ip:axis_data_fifo:* wildcards were removed on purpose: if a
# pinned IP is missing, step08 fails here with the available versions listed.

proc create_doa_v7_hier {parent name} {
    set old [current_bd_instance .]
    current_bd_instance $parent
    if {[llength [get_bd_cells -quiet $name]]} { error "BD cell $name already exists" }
    create_bd_cell -type hier $name
    current_bd_instance $name

    create_bd_pin -dir I -type clk aclk
    create_bd_pin -dir I -type rst aresetn
    set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_pins aresetn]
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS_SEARCH
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS_DOA_CAPTURE
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS_BEAM_MONITOR
    create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS_CANDIDATE
    create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS_COVARIANCE
    create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS_BEAM
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_COV_CTRL
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_CANDIDATE_CTRL
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_BEAM_CTRL

    set covariance [doa_create_pinned_ip covariance covariance]
    set power [doa_create_pinned_ip spectrum spectrum_power]
    set candidate [doa_create_pinned_ip candidate candidate_peak]
    set beam [doa_create_pinned_ip beam beam_monitor]
    set candidate_fifo [doa_create_pinned_ip axis_data_fifo candidate_fifo]
    set covariance_fifo [doa_create_pinned_ip axis_data_fifo covariance_fifo]
    set_property -dict [list CONFIG.FIFO_DEPTH {32}] $candidate_fifo
    set_property -dict [list CONFIG.FIFO_DEPTH {32}] $covariance_fifo

    connect_bd_net [get_bd_pins aclk] [get_bd_pins covariance/ap_clk] [get_bd_pins spectrum_power/ap_clk] [get_bd_pins candidate_peak/ap_clk] [get_bd_pins beam_monitor/ap_clk] [get_bd_pins candidate_fifo/s_axis_aclk] [get_bd_pins covariance_fifo/s_axis_aclk]
    connect_bd_net [get_bd_pins aresetn] [get_bd_pins covariance/ap_rst_n] [get_bd_pins spectrum_power/ap_rst_n] [get_bd_pins candidate_peak/ap_rst_n] [get_bd_pins beam_monitor/ap_rst_n] [get_bd_pins candidate_fifo/s_axis_aresetn] [get_bd_pins covariance_fifo/s_axis_aresetn]
    connect_bd_intf_net [get_bd_intf_pins S_AXIS_DOA_CAPTURE] [get_bd_intf_pins covariance/s_axis]
    connect_bd_intf_net [get_bd_intf_pins covariance/m_axis] [get_bd_intf_pins covariance_fifo/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins covariance_fifo/M_AXIS] [get_bd_intf_pins M_AXIS_COVARIANCE]
    connect_bd_intf_net [get_bd_intf_pins S_AXIS_SEARCH] [get_bd_intf_pins spectrum_power/s_axis]
    connect_bd_intf_net [get_bd_intf_pins spectrum_power/m_axis] [get_bd_intf_pins candidate_peak/s_axis]
    connect_bd_intf_net [get_bd_intf_pins candidate_peak/m_axis] [get_bd_intf_pins candidate_fifo/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins candidate_fifo/M_AXIS] [get_bd_intf_pins M_AXIS_CANDIDATE]
    connect_bd_intf_net [get_bd_intf_pins S_AXIS_BEAM_MONITOR] [get_bd_intf_pins beam_monitor/s_axis]
    connect_bd_intf_net [get_bd_intf_pins beam_monitor/m_axis] [get_bd_intf_pins M_AXIS_BEAM]
    connect_bd_intf_net [get_bd_intf_pins S_AXI_COV_CTRL] [get_bd_intf_pins covariance/s_axi_ctrl]
    connect_bd_intf_net [get_bd_intf_pins S_AXI_CANDIDATE_CTRL] [get_bd_intf_pins candidate_peak/s_axi_ctrl]
    connect_bd_intf_net [get_bd_intf_pins S_AXI_BEAM_CTRL] [get_bd_intf_pins beam_monitor/s_axi_ctrl]

    set_property CONFIG.ASSOCIATED_BUSIF {S_AXIS_SEARCH:S_AXIS_DOA_CAPTURE:S_AXIS_BEAM_MONITOR:M_AXIS_CANDIDATE:M_AXIS_COVARIANCE:M_AXIS_BEAM:S_AXI_COV_CTRL:S_AXI_CANDIDATE_CTRL:S_AXI_BEAM_CTRL} [get_bd_pins aclk]
    set_property CONFIG.ASSOCIATED_RESET {aresetn} [get_bd_pins aclk]

    current_bd_instance $old
    return [get_bd_cells $parent/$name]
}
