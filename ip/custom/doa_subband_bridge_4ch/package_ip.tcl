# Package and verify openai:doa:doa_subband_bridge_4ch:1.0 (Vivado 2023.2):
#   1. XSim self-checking RTL verification (tb_doa_subband_bridge_4ch.sv)
#   2. 250 MHz (4.000 ns) out-of-context synthesis timing gate
#   3. Vivado IP Packager export + strict VLNV verification
#   4. In-memory VHDL Block Design smoke test exercising subband_bridge,
#      axis_clock_converter, axis_dwidth_converter, axi_fifo_mm_s, xpm_cdc_gen,
#      clk_wiz, proc_sys_reset, assign_bd_address, and VHDL target generation.

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize [file join $script_dir .. .. ..]]
source [file join $root_dir common vivado common.tcl]

set build_root [expr {[info exists ::env(BUILD)] ? [file normalize $::env(BUILD)] : [file join $root_dir build]}]
set ip_repo    [expr {[info exists ::env(IP_REPO)] ? [file normalize $::env(IP_REPO)] : [file join $build_root ip_repo]}]
set ip_root    [file join $ip_repo doa_subband_bridge_4ch]
set work_root  [file join $build_root subband_bridge_work]
set report_file [file join $build_root output doa_subband_bridge_4ch_package.rpt]

set rtl_file [file join $script_dir rtl doa_subband_bridge_4ch.v]
set xdc_file [file join $script_dir rtl ooc_constraints.xdc]
set tb_file  [file join $script_dir tb tb_doa_subband_bridge_4ch.sv]

file mkdir [file dirname $report_file]
file delete -force $work_root
file mkdir $work_root
set report_fh [open $report_file w]

proc sb_log {fh msg} {
    puts $msg
    puts $fh $msg
    flush $fh
}

proc sb_read {path} {
    set fh [open $path r]
    set txt [read $fh]
    close $fh
    return $txt
}

set status FAIL
set err_msg ""
set err_info ""
set catch_rc [catch {
    sb_log $report_fh "VIVADO_VERSION=[version -short]"
    sb_log $report_fh "PART=$::PART_PINNED"

    foreach req [list $rtl_file $xdc_file $tb_file] {
        if {![file isfile $req]} {
            error "Missing required source file: $req"
        }
    }

    # -------------------------------------------------------------------------
    # 1. XSim RTL self-checking verification
    # -------------------------------------------------------------------------
    set sim_dir [file join $work_root xsim]
    file mkdir $sim_dir
    set saved_pwd [pwd]
    cd $sim_dir
    exec xvlog -work work $rtl_file >@stdout 2>@1
    exec xvlog -sv -work work $tb_file >@stdout 2>@1
    exec xelab -debug typical -timescale 1ns/1ps \
        -s tb_doa_subband_bridge_4ch_snap work.tb_doa_subband_bridge_4ch >@stdout 2>@1
    set sim_log [file join $sim_dir xsim.log]
    exec xsim tb_doa_subband_bridge_4ch_snap -runall -log $sim_log >@stdout 2>@1
    cd $saved_pwd

    if {![file isfile $sim_log]} {
        error "XSim log was not created: $sim_log"
    }
    set sim_txt [sb_read $sim_log]
    if {[string first "ALL TESTS PASSED: tb_doa_subband_bridge_4ch" $sim_txt] < 0} {
        error "XSim did not report ALL TESTS PASSED; inspect $sim_log"
    }
    sb_log $report_fh "XSIM_RESULT=PASS"

    # -------------------------------------------------------------------------
    # 2. 250 MHz (4.000 ns) out-of-context synthesis timing gate
    # -------------------------------------------------------------------------
    set ooc_dir [file join $work_root ooc_synth]
    file mkdir $ooc_dir
    create_project -in_memory -part $::PART_PINNED
    read_verilog $rtl_file
    read_xdc -mode out_of_context $xdc_file
    synth_design -top doa_subband_bridge_4ch -part $::PART_PINNED \
        -mode out_of_context -flatten_hierarchy rebuilt
    report_utilization -file [file join $ooc_dir utilization.rpt]
    report_timing_summary -delay_type min_max -max_paths 10 \
        -file [file join $ooc_dir timing_summary.rpt]
    set max_paths [get_timing_paths -max_paths 1 -setup]
    if {[llength $max_paths] == 0} {
        error "No setup timing paths found in 250 MHz OOC synthesis of doa_subband_bridge_4ch"
    }
    set ooc_wns [get_property SLACK [lindex $max_paths 0]]
    sb_log $report_fh "OOC_CLOCK_PERIOD_NS=4.000"
    sb_log $report_fh "OOC_WNS_NS=$ooc_wns"
    if {$ooc_wns eq "" || $ooc_wns < 0.0} {
        error "doa_subband_bridge_4ch failed 250 MHz OOC timing gate: WNS=$ooc_wns ns"
    }
    close_design
    close_project

    # -------------------------------------------------------------------------
    # 3. Package as openai:doa:doa_subband_bridge_4ch:1.0
    # -------------------------------------------------------------------------
    file delete -force $ip_root
    file mkdir $ip_root
    set pkg_proj_dir [file join $work_root pkg_proj]
    create_project -force doa_subband_bridge_4ch_pkg $pkg_proj_dir -part $::PART_PINNED
    add_files -norecurse $rtl_file
    set_property top doa_subband_bridge_4ch [current_fileset]
    update_compile_order -fileset sources_1

    set ip_vendor "openai"
    if {[info exists ::env(CUSTOM_IP_VENDOR)] && [string trim $::env(CUSTOM_IP_VENDOR)] ne ""} {
        set ip_vendor [string trim $::env(CUSTOM_IP_VENDOR)]
    }
    set ip_library "doa"
    if {[info exists ::env(CUSTOM_IP_LIBRARY)] && [string trim $::env(CUSTOM_IP_LIBRARY)] ne ""} {
        set ip_library [string trim $::env(CUSTOM_IP_LIBRARY)]
    }
    # Keep version strictly as a Tcl string literal (never numeric expr).
    set ip_version "1.0"
    if {[info exists ::env(IPVER_SUBBAND_BRIDGE)] && [string trim $::env(IPVER_SUBBAND_BRIDGE)] ne ""} {
        set ip_version [string trim $::env(IPVER_SUBBAND_BRIDGE)]
    }
    if {![regexp {^[0-9]+\.[0-9]+$} $ip_version]} {
        error "IPVER_SUBBAND_BRIDGE must be major.minor, got '$ip_version'"
    }

    ipx::package_project -root_dir $ip_root -vendor $ip_vendor -library $ip_library \
        -taxonomy /UserIP -import_files -set_current true
    set core [ipx::current_core]
    set_property name doa_subband_bridge_4ch $core
    set_property display_name "DOA Four-Channel Subband Stream Bridge" $core
    set_property description "250 MHz 4x SSR-8 channelizer to 512-bit /doa_v7 search/capture/beam bridge with closed-loop candidate bin tracking" $core
    set_property version $ip_version $core
    set_property supported_families {zynquplusrfsoc Production zynquplus Production} $core
    sb_log $report_fh "SUPPORTED_FAMILIES=[get_property supported_families $core]"

    set expected_busifs {
        s_axis_ch0 s_axis_ch1 s_axis_ch2 s_axis_ch3
        s_axis_candidate
        m_axis_search m_axis_capture m_axis_beam
        m_axis_mon_ch0 m_axis_mon_ch1 m_axis_mon_ch2 m_axis_mon_ch3
        s_axi_ctrl
    }
    foreach bif_name $expected_busifs {
        set bif [ipx::get_bus_interfaces $bif_name -of_objects $core]
        if {[llength $bif] == 0} {
            error "IP Packager failed to infer expected bus interface '$bif_name'"
        }
        ipx::associate_bus_interfaces -busif $bif_name -clock aclk $core
    }

    set rst_bif [ipx::get_bus_interfaces aresetn -of_objects $core]
    if {[llength $rst_bif] == 0} {
        error "IP Packager failed to infer reset interface 'aresetn'"
    }
    set rst_pol [ipx::get_bus_parameters POLARITY -of_objects $rst_bif]
    if {[llength $rst_pol] == 0} {
        set rst_pol [ipx::add_bus_parameter POLARITY $rst_bif]
    }
    set_property value ACTIVE_LOW $rst_pol

    set clk_bif [ipx::get_bus_interfaces aclk -of_objects $core]
    if {[llength $clk_bif] == 0} {
        error "IP Packager failed to infer clock interface 'aclk'"
    }
    set clk_busif [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $clk_bif]
    if {[llength $clk_busif] == 0} {
        set clk_busif [ipx::add_bus_parameter ASSOCIATED_BUSIF $clk_bif]
    }
    set_property value [join $expected_busifs ":"] $clk_busif
    set clk_rst [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects $clk_bif]
    if {[llength $clk_rst] == 0} {
        set clk_rst [ipx::add_bus_parameter ASSOCIATED_RESET $clk_bif]
    }
    set_property value aresetn $clk_rst
    sb_log $report_fh "ACLK_ASSOCIATED_BUSIF=[get_property value $clk_busif]"
    sb_log $report_fh "ACLK_ASSOCIATED_RESET=[get_property value $clk_rst]"

    # Ensure s_axi_ctrl memory map advertises >= 4 KB so SmartConnect / AXI Interconnect
    # assign_bd_address cleanly allocates a standard 4 KB / 64 KB slave window.
    set mm [ipx::get_memory_maps s_axi_ctrl -of_objects $core]
    if {[llength $mm] == 0} {
        error "IP Packager failed to infer memory map for s_axi_ctrl"
    }
    set ab [ipx::get_address_blocks -of_objects $mm]
    if {[llength $ab] == 0} {
        error "IP Packager failed to infer address block for s_axi_ctrl"
    }
    set_property range 4096 [lindex $ab 0]

    ipx::create_xgui_files $core
    ipx::update_checksums $core
    ipx::check_integrity $core
    ipx::save_core $core
    close_project

    set comp_xml [file join $ip_root component.xml]
    set expected_vlnv [doa_vlnv subband_bridge]
    exec bash [file join $root_dir common scripts check_component_vlnv.sh] $comp_xml $expected_vlnv >@stdout 2>@1
    sb_log $report_fh "PACKAGED_VLNV=$expected_vlnv"
    sb_log $report_fh "COMPONENT_XML=$comp_xml"

    # -------------------------------------------------------------------------
    # 4. VHDL Block Design smoke test (validates IPI instantiation + helper IPs)
    # -------------------------------------------------------------------------
    set bd_proj_dir [file join $work_root vhdl_bd_smoke]
    create_project -force subband_bridge_bd_smoke $bd_proj_dir -part $::PART_PINNED
    set_property target_language VHDL [current_project]
    set_property ip_repo_paths [list $ip_repo] [current_project]
    update_ip_catalog -rebuild

    create_bd_design smoke_bd
    set clk250 [create_bd_port -dir I -type clk -freq_hz 250000000 clk_250m]
    set clk500 [create_bd_port -dir I -type clk -freq_hz 500000000 clk_500m]
    set rst250 [create_bd_port -dir I -type rst rst_250m_n]
    set_property CONFIG.POLARITY ACTIVE_LOW $rst250
    set sysref_in [create_bd_port -dir I sysref_500m]
    set sysref_out [create_bd_port -dir O sysref_250m]

    set s_axi_ext [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_EXT]
    set_property -dict [list \
        CONFIG.PROTOCOL {AXI4LITE} \
        CONFIG.ADDR_WIDTH {32} \
        CONFIG.DATA_WIDTH {32} \
    ] $s_axi_ext
    set_property CONFIG.ASSOCIATED_BUSIF {S_AXI_EXT} $clk250
    set_property CONFIG.ASSOCIATED_RESET {rst_250m_n} $clk250

    set clk_doa [doa_create_pinned_ip clk_wiz clk_doa]
    set_property -dict [list \
        CONFIG.PRIM_SOURCE {No_buffer} \
        CONFIG.PRIM_IN_FREQ {250.000} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125.000} \
        CONFIG.USE_RESET {false} \
        CONFIG.USE_LOCKED {true} \
    ] $clk_doa

    set rst_doa [doa_create_pinned_ip proc_sys_reset rst_doa]

    set sysref_cdc [doa_create_pinned_ip xpm_cdc_gen sysref_cdc]
    set_property -dict [list \
        CONFIG.CDC_TYPE {xpm_cdc_single} \
        CONFIG.SRC_INPUT_REG {1} \
        CONFIG.DEST_SYNC_FF {2} \
        CONFIG.WIDTH {1} \
    ] $sysref_cdc

    set bridge_0 [doa_create_pinned_ip subband_bridge bridge_0]

    set cdc_beam [doa_create_pinned_ip axis_clock_converter cdc_beam]
    set_property CONFIG.IS_ACLK_ASYNC {1} $cdc_beam

    set dw_beam [doa_create_pinned_ip axis_dwidth_converter dw_beam]
    set_property CONFIG.M_TDATA_NUM_BYTES {4} $dw_beam

    set fifo_beam [doa_create_pinned_ip axi_fifo_mm_s fifo_beam]
    set_property -dict [list \
        CONFIG.C_DATA_INTERFACE_TYPE {0} \
        CONFIG.C_USE_TX_DATA {0} \
        CONFIG.C_USE_TX_CTRL {0} \
        CONFIG.C_USE_RX_DATA {1} \
        CONFIG.C_RX_FIFO_DEPTH {2048} \
    ] $fifo_beam

    set ctrl_sc [doa_create_pinned_ip smartconnect ctrl_sc]
    set_property -dict [list \
        CONFIG.NUM_SI {1} \
        CONFIG.NUM_MI {2} \
        CONFIG.NUM_CLKS {2} \
    ] $ctrl_sc

    # Clocks & resets
    connect_bd_net $clk250 [get_bd_pins $clk_doa/clk_in1]
    set clk125 [get_bd_pins $clk_doa/clk_out1]
    connect_bd_net $clk125 [get_bd_pins $rst_doa/slowest_sync_clk]
    connect_bd_net $rst250 [get_bd_pins $rst_doa/ext_reset_in]
    connect_bd_net [get_bd_pins $clk_doa/locked] [get_bd_pins $rst_doa/dcm_locked]
    set rst125 [get_bd_pins $rst_doa/peripheral_aresetn]

    connect_bd_net $clk500 [get_bd_pins $sysref_cdc/src_clk]
    connect_bd_net $clk250 [get_bd_pins $sysref_cdc/dest_clk]
    connect_bd_net $sysref_in [get_bd_pins $sysref_cdc/src_in]
    connect_bd_net [get_bd_pins $sysref_cdc/dest_out] $sysref_out

    connect_bd_net $clk250 [get_bd_pins $bridge_0/aclk] [get_bd_pins $cdc_beam/s_axis_aclk] [get_bd_pins $ctrl_sc/aclk]
    connect_bd_net $rst250 [get_bd_pins $bridge_0/aresetn] [get_bd_pins $cdc_beam/s_axis_aresetn] [get_bd_pins $ctrl_sc/aresetn]
    connect_bd_net $clk125 [get_bd_pins $cdc_beam/m_axis_aclk] [get_bd_pins $dw_beam/aclk] [get_bd_pins $fifo_beam/s_axi_aclk] [get_bd_pins $ctrl_sc/aclk1]
    connect_bd_net $rst125 [get_bd_pins $cdc_beam/m_axis_aresetn] [get_bd_pins $dw_beam/aresetn] [get_bd_pins $fifo_beam/s_axi_aresetn]

    # AXI-Stream chain: 512b@250MHz -> 512b@125MHz -> 32b@125MHz -> axi_fifo_mm_s
    connect_bd_intf_net [get_bd_intf_pins $bridge_0/m_axis_beam] [get_bd_intf_pins $cdc_beam/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins $cdc_beam/M_AXIS] [get_bd_intf_pins $dw_beam/S_AXIS]
    set fifo_rx_pin [get_bd_intf_pins -of_objects $fifo_beam -filter {VLNV == "xilinx.com:interface:axis_rtl:1.0" && MODE == "Slave"}]
    if {[llength $fifo_rx_pin] != 1} {
        error "Expected exactly 1 slave AXIS pin on axi_fifo_mm_s, found: $fifo_rx_pin"
    }
    connect_bd_intf_net [get_bd_intf_pins $dw_beam/M_AXIS] [lindex $fifo_rx_pin 0]

    # AXI4-Lite control
    connect_bd_intf_net $s_axi_ext [get_bd_intf_pins $ctrl_sc/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins $ctrl_sc/M00_AXI] [get_bd_intf_pins $bridge_0/s_axi_ctrl]
    connect_bd_intf_net [get_bd_intf_pins $ctrl_sc/M01_AXI] [get_bd_intf_pins $fifo_beam/S_AXI]

    assign_bd_address
    validate_bd_design
    save_bd_design
    set bd_file [get_files *smoke_bd.bd]
    generate_target synthesis $bd_file
    close_project
    sb_log $report_fh "VHDL_BD_SMOKE_RESULT=PASS"

    set status PASS
} err_msg err_info]

if {$catch_rc != 0} {
    sb_log $report_fh "ERROR=$err_msg"
    sb_log $report_fh "ERROR_INFO=$err_info"
}
sb_log $report_fh "DOA SUBBAND BRIDGE PACKAGE RESULT=$status"
close $report_fh
if {$catch_rc != 0} { exit 1 }
exit 0
