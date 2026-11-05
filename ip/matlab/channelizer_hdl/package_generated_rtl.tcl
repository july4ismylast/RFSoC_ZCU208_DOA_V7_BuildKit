# Usage: vivado -mode batch -source package_generated_rtl.tcl -tclargs <rtl_dir> <top> [part] [wrapper_file]
# Stage V06 Gate 5: package channelizer_axis_wrapper + transposed Channelizer_DUT
# as openai:doa:matlab_channelizer:7.0, verify VLNV + IPX integrity, and smoke-test
# instantiation + VHDL BD target generation in Vivado 2023.2.

if {[llength $argv] < 2} { error "Need rtl_dir and top_module" }
set rtl_dir [file normalize [lindex $argv 0]]
set top     [lindex $argv 1]
set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize [file join $script_dir .. .. ..]]
source [file join $root_dir common vivado common.tcl]

set part [expr {[llength $argv] > 2 ? [lindex $argv 2] : $::PART_PINNED}]
set wrapper_file [expr {[llength $argv] > 3 ? [file normalize [lindex $argv 3]] : [file join $script_dir channelizer_axis_wrapper.sv]}]
set build_root [expr {[info exists ::env(BUILD)] ? [file normalize $::env(BUILD)] : [file join $root_dir build]}]
set ip_repo    [expr {[info exists ::env(IP_REPO)] ? [file normalize $::env(IP_REPO)] : [file join $build_root ip_repo]}]
set ip_root    [file join $ip_repo matlab_channelizer]
set work_root  [file join $build_root v06_gate5_package]
set report_file [file join $build_root output v06_gate5_package.rpt]

file mkdir [file dirname $report_file]
file delete -force $work_root
file mkdir $work_root
set report_fh [open $report_file w]

proc g5_log {fh msg} {
    puts $msg
    puts $fh $msg
    flush $fh
}

proc collect_hdl_files {dir} {
    set result {}
    foreach entry [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $entry]} {
            set result [concat $result [collect_hdl_files $entry]]
        } elseif {[regexp -nocase {\.(v|sv|vhd|vhdl)$} [file extension $entry]]} {
            lappend result [file normalize $entry]
        }
    }
    return $result
}

set status FAIL
set err_msg ""
set err_info ""
set catch_rc [catch {
    g5_log $report_fh "VIVADO_VERSION=[version -short]"
    g5_log $report_fh "PART=$part"
    g5_log $report_fh "RTL_DIR=$rtl_dir"
    g5_log $report_fh "PACKAGE_TOP=$top"

    set files [lsort -unique [collect_hdl_files $rtl_dir]]
    if {[llength $files] == 0} {
        error "No generated HDL files found recursively under $rtl_dir"
    }
    if {$top eq "channelizer_axis_wrapper"} {
        if {![file isfile $wrapper_file]} {
            error "AXI4-Stream wrapper file is missing: $wrapper_file"
        }
        lappend files $wrapper_file
        set files [lsort -unique $files]
    }

    set top_matches {}
    set dut_matches {}
    foreach hdl_file $files {
        set rname [file rootname [file tail $hdl_file]]
        if {$rname eq $top} {
            lappend top_matches $hdl_file
        }
        if {$rname eq "Channelizer_DUT"} {
            lappend dut_matches $hdl_file
        }
    }
    if {[llength $top_matches] == 0} {
        error "Top module '$top' was not found in packaged file set"
    }
    if {[llength $dut_matches] == 0} {
        error "Generated core 'Channelizer_DUT' was not found under $rtl_dir"
    }
    g5_log $report_fh "PACKAGED_HDL_FILE_COUNT=[llength $files]"
    g5_log $report_fh "TOP_SOURCE=[lindex $top_matches 0]"
    g5_log $report_fh "DUT_SOURCE=[lindex $dut_matches 0]"

    file delete -force $ip_root
    file mkdir $ip_root
    set pkg_proj_dir [file join $work_root matlab_channelizer_pkg]
    create_project -force matlab_channelizer_pkg $pkg_proj_dir -part $part
    add_files -norecurse $files
    set_property top $top [current_fileset]
    update_compile_order -fileset sources_1

    set ip_vendor "openai"
    if {[info exists ::env(CUSTOM_IP_VENDOR)] && [string trim $::env(CUSTOM_IP_VENDOR)] ne ""} {
        set ip_vendor [string trim $::env(CUSTOM_IP_VENDOR)]
    }
    set ip_library "doa"
    if {[info exists ::env(CUSTOM_IP_LIBRARY)] && [string trim $::env(CUSTOM_IP_LIBRARY)] ne ""} {
        set ip_library [string trim $::env(CUSTOM_IP_LIBRARY)]
    }
    # Keep the version strictly as a Tcl string literal (never numeric expr).
    set ip_version "7.0"
    if {[info exists ::env(IPVER_CHANNELIZER)] && [string trim $::env(IPVER_CHANNELIZER)] ne ""} {
        set ip_version [string trim $::env(IPVER_CHANNELIZER)]
    }
    if {![regexp {^[0-9]+\.[0-9]+$} $ip_version]} {
        error "IPVER_CHANNELIZER must be a major.minor version string, got '$ip_version'"
    }

    ipx::package_project -root_dir $ip_root -vendor $ip_vendor -library $ip_library \
        -taxonomy /UserIP -import_files -set_current true
    set core [ipx::current_core]
    set_property name matlab_channelizer $core
    set_property display_name "MATLAB DSP HDL SSR-8 1024-Band Transposed Channelizer" $core
    set_property description "Single-channel 2.0 GSPS complex SSR-8 1024-band transposed polyphase FFT channelizer with AXI4-Stream wrapper (256-bit in -> 416-bit out)" $core
    set_property version $ip_version $core
    set_property supported_families {zynquplusRFSOC Production zynquplus Production} $core

    if {$top eq "channelizer_axis_wrapper"} {
        foreach bif_name {s_axis m_axis} {
            set bif [ipx::get_bus_interfaces $bif_name -of_objects $core]
            if {[llength $bif] == 0} {
                error "IP Packager failed to infer AXI4-Stream interface '$bif_name' on $top"
            }
            ipx::associate_bus_interfaces -busif $bif_name -clock aclk $core
        }
        set rst_bif [ipx::get_bus_interfaces aresetn -of_objects $core]
        if {[llength $rst_bif] == 0} {
            error "IP Packager failed to infer reset interface 'aresetn' on $top"
        }
        set rst_pol [ipx::get_bus_parameters POLARITY -of_objects $rst_bif]
        if {[llength $rst_pol] == 0} {
            set rst_pol [ipx::add_bus_parameter POLARITY $rst_bif]
        }
        set_property value ACTIVE_LOW $rst_pol

        set clk_bif [ipx::get_bus_interfaces aclk -of_objects $core]
        if {[llength $clk_bif] == 0} {
            error "IP Packager failed to infer clock interface 'aclk' on $top"
        }
        set clk_rst [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects $clk_bif]
        if {[llength $clk_rst] == 0} {
            set clk_rst [ipx::add_bus_parameter ASSOCIATED_RESET $clk_bif]
        }
        set_property value aresetn $clk_rst
    }

    ipx::create_xgui_files $core
    ipx::update_checksums $core
    ipx::check_integrity $core
    ipx::save_core $core
    close_project

    set comp_xml [file join $ip_root component.xml]
    set expected_vlnv [doa_vlnv channelizer]
    exec bash [file join $root_dir common scripts check_component_vlnv.sh] $comp_xml $expected_vlnv >@stdout 2>@1
    g5_log $report_fh "PACKAGED_VLNV=$expected_vlnv"
    g5_log $report_fh "COMPONENT_XML=$comp_xml"

    # VHDL Block Design instantiation & target-generation smoke test
    if {$top eq "channelizer_axis_wrapper"} {
        set bd_proj_dir [file join $work_root vhdl_bd_smoke]
        create_project -force channelizer_bd_smoke $bd_proj_dir -part $part
        set_property target_language VHDL [current_project]
        set_property ip_repo_paths [list $ip_repo] [current_project]
        update_ip_catalog -rebuild

        create_bd_design chan_smoke_bd
        set clk250 [create_bd_port -dir I -type clk -freq_hz 250000000 aclk]
        set rst250 [create_bd_port -dir I -type rst aresetn]
        set_property CONFIG.POLARITY ACTIVE_LOW $rst250
        set s_in  [create_bd_intf_port -mode Slave  -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS]
        set m_out [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS]
        set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.HAS_TREADY {1} CONFIG.HAS_TLAST {0}] $s_in
        set_property CONFIG.ASSOCIATED_BUSIF {S_AXIS:M_AXIS} $clk250
        set_property CONFIG.ASSOCIATED_RESET {aresetn} $clk250

        set ch0 [doa_create_pinned_ip channelizer ch0]
        connect_bd_net $clk250 [get_bd_pins $ch0/aclk]
        connect_bd_net $rst250 [get_bd_pins $ch0/aresetn]
        connect_bd_intf_net $s_in [get_bd_intf_pins $ch0/s_axis]
        connect_bd_intf_net [get_bd_intf_pins $ch0/m_axis] $m_out

        validate_bd_design
        set s_bytes [get_property CONFIG.TDATA_NUM_BYTES [get_bd_intf_pins $ch0/s_axis]]
        set m_bytes [get_property CONFIG.TDATA_NUM_BYTES [get_bd_intf_pins $ch0/m_axis]]
        g5_log $report_fh "BD_S_AXIS_BYTES=$s_bytes"
        g5_log $report_fh "BD_M_AXIS_BYTES=$m_bytes"
        if {$s_bytes != 32 || $m_bytes != 52} {
            error "Unexpected BD TDATA_NUM_BYTES on packaged channelizer: s_axis=$s_bytes (exp 32), m_axis=$m_bytes (exp 52)"
        }
        save_bd_design
        generate_target synthesis [get_files *chan_smoke_bd.bd]
        close_project
        g5_log $report_fh "VHDL_BD_SMOKE_RESULT=PASS"
    }

    set status PASS
} err_msg err_info]

if {$catch_rc != 0} {
    g5_log $report_fh "ERROR=$err_msg"
    g5_log $report_fh "ERROR_INFO=$err_info"
}
g5_log $report_fh "V06 GATE5 PACKAGE RESULT=$status"
close $report_fh
puts "Packaged MATLAB-generated RTL at $ip_root (RESULT=$status)"
if {$catch_rc != 0} { exit 1 }
exit 0
