# config/zcu208_bd_map.tcl
# Stage V07 production ZCU208 MTS + DOA V7 Block Design integration layer.
#
# Modes:
#   mapped         - Full ZCU208 RFSoC-MTS integration (default in config.mk):
#                      * exports 4th analog ADC pair vin1_23
#                      * applies V04 staged RFDC 4-ch Zone-2 R2C 2x DDC + MTS restore
#                      * moves ADC AXIS clocks/resets + user_sysref_adc to 250 MHz
#                      * derives 125 MHz /doa_v7 clock/reset from clkRFdiv2
#                      * wires rfdc_repack4 -> 4x matlab_channelizer -> doa_subband_bridge_4ch
#                      * wires 4x async axis_clock_converter + 2x PS AXI-Stream RX FIFOs
#                      * attaches all 6 DOA AXI4-Lite slaves to /control_interconnect
#   external_ports - Structural-only smoke mode (not placeable on ZU48DR).

namespace eval ::doa_bd_map {
    proc log {fh msg} {
        puts $msg
        if {$fh ne ""} {
            puts $fh $msg
            flush $fh
        }
    }

    proc get_prop {prop obj} {
        if {[catch {set v [get_property $prop $obj]}]} { return "<unavailable>" }
        return $v
    }

    proc num_eq {a b} {
        if {[catch {expr {abs(double($a) - double($b))}} d]} { return 0 }
        return [expr {$d < 1e-6}]
    }

    proc bool_true {v} {
        return [expr {$v eq "true" || $v eq "TRUE" || $v eq "1"}]
    }

    proc require_cell {path} {
        set c [get_bd_cells -quiet $path]
        if {[llength $c] != 1} {
            error "Required BD cell '$path' not found in [current_bd_design] (got: $c)"
        }
        return [lindex $c 0]
    }

    proc require_pin {path} {
        set p [get_bd_pins -quiet $path]
        if {[llength $p] != 1} {
            error "Required BD pin '$path' not found in [current_bd_design] (got: $p)"
        }
        return [lindex $p 0]
    }

    proc require_intf_pin {path} {
        set p [get_bd_intf_pins -quiet $path]
        if {[llength $p] != 1} {
            error "Required BD interface pin '$path' not found in [current_bd_design] (got: $p)"
        }
        return [lindex $p 0]
    }

    proc disconnect_intf_pin {path} {
        set ipin [get_bd_intf_pins -quiet $path]
        if {[llength $ipin] == 1} {
            set inet [get_bd_intf_nets -quiet -of_objects $ipin]
            if {[llength $inet] > 0} {
                delete_bd_objs $inet
            }
        }
    }

    proc rewire_scalar_pin {pin_path driver_pin} {
        set pin [require_pin $pin_path]
        set cur_net [lindex [get_bd_nets -quiet -of_objects $pin] 0]
        set drv_net [lindex [get_bd_nets -quiet -of_objects $driver_pin] 0]
        if {$cur_net ne "" && $cur_net eq $drv_net} {
            return
        }
        if {$cur_net ne ""} {
            disconnect_bd_net $cur_net $pin
        }
        connect_bd_net $driver_pin $pin
    }

    proc capture_sysref_driver_500m {rfdc} {
        # Inspect user_sysref_dac first so idempotent reruns on an already-mapped
        # BD still capture the original 500 MHz /clocktreeMTS SYSREF output pin.
        foreach syspin {user_sysref_dac user_sysref_adc} {
            set pin [lindex [get_bd_pins -quiet "$rfdc/$syspin"] 0]
            if {$pin eq ""} { continue }
            set net [lindex [get_bd_nets -quiet -of_objects $pin] 0]
            if {$net eq ""} { continue }
            foreach peer [get_bd_pins -quiet -of_objects $net] {
                if {$peer eq $pin} { continue }
                if {[string match "$rfdc/*" $peer]} { continue }
                if {[string match "/doa_sysref_adc_cdc/*" $peer]} { continue }
                if {[get_prop DIR $peer] eq "O"} {
                    return $peer
                }
            }
            foreach peer [get_bd_pins -quiet -of_objects $net] {
                if {$peer ne $pin && ![string match "$rfdc/*" $peer] && ![string match "/doa_sysref_adc_cdc/*" $peer]} {
                    return $peer
                }
            }
        }
        return ""
    }

    proc build_rfdc_pair_dict {groups pair_ids} {
        set d [dict create]
        foreach grp $groups {
            lassign $grp prefix val
            foreach xx $pair_ids {
                dict set d "CONFIG.ADC_${prefix}${xx}" $val
            }
        }
        return $d
    }

    proc mts_all_true {rfdc} {
        return [expr {[bool_true [get_prop CONFIG.ADC0_Multi_Tile_Sync $rfdc]] && \
                      [bool_true [get_prop CONFIG.ADC1_Multi_Tile_Sync $rfdc]] && \
                      [bool_true [get_prop CONFIG.DAC0_Multi_Tile_Sync $rfdc]] && \
                      [bool_true [get_prop CONFIG.DAC1_Multi_Tile_Sync $rfdc]]}]
    }

    proc restore_and_assert_mts {fh rfdc label} {
        if {![mts_all_true $rfdc]} {
            catch {
                set_property -dict [list \
                    CONFIG.ADC0_Multi_Tile_Sync {true} \
                    CONFIG.ADC1_Multi_Tile_Sync {true} \
                    CONFIG.DAC0_Multi_Tile_Sync {true} \
                    CONFIG.DAC1_Multi_Tile_Sync {true} \
                ] $rfdc
            }
        }
        if {![mts_all_true $rfdc]} {
            # V04 fallback: enable ADC as sole MTS group, then re-enable DAC MTS.
            catch {
                set_property -dict [list \
                    CONFIG.ADC0_Multi_Tile_Sync {true} \
                    CONFIG.ADC1_Multi_Tile_Sync {true} \
                    CONFIG.DAC0_Multi_Tile_Sync {false} \
                    CONFIG.DAC1_Multi_Tile_Sync {false} \
                ] $rfdc
                set_property -dict [list \
                    CONFIG.DAC0_Multi_Tile_Sync {true} \
                    CONFIG.DAC1_Multi_Tile_Sync {true} \
                ] $rfdc
            }
        }
        log $fh "MTS CHECK ($label): ADC0=[get_prop CONFIG.ADC0_Multi_Tile_Sync $rfdc] ADC1=[get_prop CONFIG.ADC1_Multi_Tile_Sync $rfdc] DAC0=[get_prop CONFIG.DAC0_Multi_Tile_Sync $rfdc] DAC1=[get_prop CONFIG.DAC1_Multi_Tile_Sync $rfdc]"
        if {![mts_all_true $rfdc]} {
            error "RFDC Multi-Tile Sync invariant failed at '$label': ADC0=[get_prop CONFIG.ADC0_Multi_Tile_Sync $rfdc] ADC1=[get_prop CONFIG.ADC1_Multi_Tile_Sync $rfdc] DAC0=[get_prop CONFIG.DAC0_Multi_Tile_Sync $rfdc] DAC1=[get_prop CONFIG.DAC1_Multi_Tile_Sync $rfdc]"
        }
    }
}

proc doa_post_validate_assertions {{fh ""}} {
    set rfdc [::doa_bd_map::require_cell /usp_rf_data_converter_1]
    ::doa_bd_map::restore_and_assert_mts $fh $rfdc "post-validate"

    foreach tile {0 1} {
        set fab [::doa_bd_map::get_prop "CONFIG.ADC${tile}_Fabric_Freq" $rfdc]
        if {![::doa_bd_map::num_eq $fab 250.000]} {
            error "Expected RFDC CONFIG.ADC${tile}_Fabric_Freq=250.000, got '$fab'"
        }
    }
    set pl_clk [::doa_bd_map::get_prop CONFIG.PL_Clock_Freq $rfdc]
    if {![::doa_bd_map::num_eq $pl_clk 500.000]} {
        error "Expected RFDC CONFIG.PL_Clock_Freq=500.000, got '$pl_clk'"
    }

    foreach port [get_bd_intf_ports -quiet] {
        set vlnv [::doa_bd_map::get_prop VLNV $port]
        if {$vlnv eq "xilinx.com:interface:axis_rtl:1.0" || $vlnv eq "xilinx.com:interface:aximm_rtl:1.0"} {
            error "External fabric AXI/AXIS port '$port' ($vlnv) is illegal in mapped production mode"
        }
    }
}

proc connect_doa_v7_to_base {hier integration_mode} {
    if {$integration_mode eq "external_ports"} {
        foreach pin {S_AXIS_SEARCH S_AXIS_DOA_CAPTURE S_AXIS_BEAM_MONITOR M_AXIS_CANDIDATE M_AXIS_COVARIANCE M_AXIS_BEAM S_AXI_COV_CTRL S_AXI_CANDIDATE_CTRL S_AXI_BEAM_CTRL} {
            make_bd_intf_pins_external [get_bd_intf_pins ${hier}/${pin}]
        }
        make_bd_pins_external [get_bd_pins ${hier}/aclk]
        make_bd_pins_external [get_bd_pins ${hier}/aresetn]
        puts "WARNING: DOA ports were externalized for structural validation only. This is not a deployable RFDC connection."
        return
    }
    if {$integration_mode ne "mapped"} {
        error "Unsupported INTEGRATION_MODE='$integration_mode' (expected 'mapped' or 'external_ports')"
    }

    set flow [expr {[info exists ::env(CHANNELIZER_FLOW)] ? [string trim $::env(CHANNELIZER_FLOW)] : "matlab_hdl"}]
    if {$flow ne "matlab_hdl"} {
        error "ZCU208 mapped BD integration currently targets the locked Plan-A flow CHANNELIZER_FLOW=matlab_hdl (got '$flow')"
    }

    set out_dir [ensure_output_directory]
    set rpt_path [file join $out_dir v07_bd_integration.rpt]
    set fh [open $rpt_path w]
    set saved_inst [current_bd_instance .]
    current_bd_instance /

    set rc [catch {
        ::doa_bd_map::log $fh "=== V07 ZCU208 MAPPED BD INTEGRATION ==="
        ::doa_bd_map::log $fh "VIVADO_VERSION=[version -short]"
        ::doa_bd_map::log $fh "BD_DESIGN=[current_bd_design]"
        ::doa_bd_map::log $fh "DOA_HIER=/$hier"

        # ---------------------------------------------------------------------
        # 1. Verify MTS base cells & capture clocks/resets/SYSREF source
        # ---------------------------------------------------------------------
        set rfdc      [::doa_bd_map::require_cell /usp_rf_data_converter_1]
        set clktree   [::doa_bd_map::require_cell /clocktreeMTS]
        set ctrl_ic   [::doa_bd_map::require_cell /control_interconnect]
        set ps_cell   [::doa_bd_map::require_cell /zynq_ultra_ps_e_0]
        set adc0_cap  [::doa_bd_map::require_cell /hier_adc0_cap]
        set adc1_cap  [::doa_bd_map::require_cell /hier_adc1_cap]
        set adc2_cap  [::doa_bd_map::require_cell /hier_adc2_cap]
        set deep_cap  [::doa_bd_map::require_cell /deepCapture]

        set clk_rf_500m   [::doa_bd_map::require_pin /clocktreeMTS/clkRF]
        set clk_rf_250m   [::doa_bd_map::require_pin /clocktreeMTS/clkRFdiv2]
        set rst_rf_250m_n [::doa_bd_map::require_pin /clocktreeMTS/egress_aresetn]
        set pl_resetn0    [::doa_bd_map::require_pin /zynq_ultra_ps_e_0/pl_resetn0]

        set sysref_500m_drv [::doa_bd_map::capture_sysref_driver_500m $rfdc]
        if {$sysref_500m_drv eq ""} {
            error "Could not locate 500 MHz user_sysref driver pin for $rfdc"
        }
        ::doa_bd_map::log $fh "SYSREF_500M_DRIVER=$sysref_500m_drv"

        # Remove any external test ports left over from an earlier external_ports run
        foreach stale_port [get_bd_intf_ports -quiet {S_AXIS_* M_AXIS_* S_AXI_*_CTRL*}] {
            delete_bd_objs $stale_port
        }
        foreach stale_port [get_bd_ports -quiet {aclk* aresetn*}] {
            delete_bd_objs $stale_port
        }

        # Idempotent cleanup of prior V07 helper cells
        set helper_cells {
            /doa_sysref_adc_cdc
            /doa_clk_wiz_125m
            /doa_rst_125m
            /doa_rfdc_repack_0
            /doa_channelizer_0
            /doa_channelizer_1
            /doa_channelizer_2
            /doa_channelizer_3
            /doa_subband_bridge_0
            /doa_cdc_search
            /doa_cdc_capture
            /doa_cdc_beam
            /doa_cdc_candidate
            /doa_cov_dwc
            /doa_cov_fifo
            /doa_beam_dwc
            /doa_beam_fifo
        }
        foreach hc $helper_cells {
            set existing [get_bd_cells -quiet $hc]
            if {[llength $existing] > 0} {
                delete_bd_objs $existing
            }
        }

        # ---------------------------------------------------------------------
        # 2. Detach legacy 500 MHz real ADC capture streams & move their stream
        #    clocks to 250 MHz clkRFdiv2 so their resets/FIFOs remain valid.
        # ---------------------------------------------------------------------
        foreach cap_axis {/hier_adc0_cap/S_AXIS /hier_adc1_cap/S_AXIS /hier_adc2_cap/S_AXIS /deepCapture/S_AXIS} {
            ::doa_bd_map::disconnect_intf_pin $cap_axis
        }
        foreach rfdc_m {m00_axis m01_axis m02_axis m03_axis m10_axis m11_axis m12_axis m13_axis} {
            ::doa_bd_map::disconnect_intf_pin "$rfdc/$rfdc_m"
        }
        foreach cap_clk {/hier_adc0_cap/aclk /hier_adc1_cap/aclk /hier_adc2_cap/aclk /deepCapture/s_axis_aclk} {
            ::doa_bd_map::rewire_scalar_pin $cap_clk $clk_rf_250m
        }

        # ---------------------------------------------------------------------
        # 3. Export 4th analog input vin1_23 & apply V04 staged RFDC config
        # ---------------------------------------------------------------------
        set vin1_23_pin [::doa_bd_map::require_intf_pin "$rfdc/vin1_23"]
        if {[llength [get_bd_intf_nets -quiet -of_objects $vin1_23_pin]] == 0} {
            make_bd_intf_pins_external $vin1_23_pin
            ::doa_bd_map::log $fh "EXPORTED_ANALOG_PORT=vin1_23"
        }

        set rf_center_hz [expr {[info exists ::env(RF_CENTER_HZ)] ? double($::env(RF_CENTER_HZ)) : 3000000000.0}]
        set nco_ghz [format "%.6f" [expr {-1.0 * $rf_center_hz / 1.0e9}]]
        set rfdc_pl_mhz [expr {[info exists ::env(RFDC_PL_CLOCK_HZ)] ? [format "%.3f" [expr {double($::env(RFDC_PL_CLOCK_HZ)) / 1.0e6}]] : "500.000"}]
        set pair_ids {00 02 10 12}

        # Stage 1: R2C Fine mixer mode across all 4 ADC pairs
        set_property -dict [::doa_bd_map::build_rfdc_pair_dict {{Data_Type 1} {Mixer_Mode 0} {Mixer_Type 2}} $pair_ids] $rfdc
        # Pre-Stage-2: explicit 500 MHz common MTS PL clock (V04 v1.3 proof)
        set_property CONFIG.PL_Clock_Freq $rfdc_pl_mhz $rfdc
        # Stage 2: atomic 8-word 2x decimation across both ADC tiles
        if {[catch {
            set_property -dict [::doa_bd_map::build_rfdc_pair_dict {{Data_Width 8} {Decimation_Mode 2}} $pair_ids] $rfdc
        }]} {
            foreach tile_pairs {{00 02} {10 12}} {
                set_property -dict [::doa_bd_map::build_rfdc_pair_dict {{Data_Width 8} {Decimation_Mode 2}} $tile_pairs] $rfdc
            }
        }
        # Stage 3: Zone-2 NCO (-F_C) + CalOpt Mode 2
        set_property -dict [::doa_bd_map::build_rfdc_pair_dict [list [list NCO_Freq $nco_ghz] {NCO_Phase 0} {Nyquist 1} {CalOpt_Mode 1}] $pair_ids] $rfdc

        foreach tile {0 1} {
            set cur_fab [::doa_bd_map::get_prop "CONFIG.ADC${tile}_Fabric_Freq" $rfdc]
            if {![::doa_bd_map::num_eq $cur_fab 250.000]} {
                catch { set_property "CONFIG.ADC${tile}_Fabric_Freq" 250.000 $rfdc }
            }
        }

        # Rewire ADC AXIS clocks/resets to 250 MHz clkRFdiv2 / egress_aresetn
        ::doa_bd_map::rewire_scalar_pin "$rfdc/m0_axis_aclk"    $clk_rf_250m
        ::doa_bd_map::rewire_scalar_pin "$rfdc/m1_axis_aclk"    $clk_rf_250m
        ::doa_bd_map::rewire_scalar_pin "$rfdc/m0_axis_aresetn" $rst_rf_250m_n
        ::doa_bd_map::rewire_scalar_pin "$rfdc/m1_axis_aresetn" $rst_rf_250m_n

        # Restore ADC0/1 + DAC0/1 Multi-Tile Sync
        ::doa_bd_map::restore_and_assert_mts $fh $rfdc "after-rfdc-apply"

        # Split PL SYSREF capture: keep user_sysref_dac on 500 MHz clkRF and
        # synchronize user_sysref_adc into 250 MHz clkRFdiv2 via xpm_cdc_gen.
        set sysref_cdc [doa_create_pinned_ip xpm_cdc_gen doa_sysref_adc_cdc]
        set_property -dict [list \
            CONFIG.CDC_TYPE {xpm_cdc_single} \
            CONFIG.SRC_INPUT_REG {1} \
            CONFIG.DEST_SYNC_FF {2} \
            CONFIG.WIDTH {1} \
        ] $sysref_cdc
        connect_bd_net $clk_rf_500m     [::doa_bd_map::require_pin "$sysref_cdc/src_clk"]
        connect_bd_net $clk_rf_250m     [::doa_bd_map::require_pin "$sysref_cdc/dest_clk"]
        connect_bd_net $sysref_500m_drv [::doa_bd_map::require_pin "$sysref_cdc/src_in"]

        ::doa_bd_map::rewire_scalar_pin "$rfdc/user_sysref_dac" $sysref_500m_drv
        ::doa_bd_map::rewire_scalar_pin "$rfdc/user_sysref_adc" [::doa_bd_map::require_pin "$sysref_cdc/dest_out"]

        foreach req_m {m00_axis m01_axis m02_axis m03_axis m10_axis m11_axis m12_axis m13_axis} {
            ::doa_bd_map::require_intf_pin "$rfdc/$req_m"
        }
        ::doa_bd_map::log $fh "RFDC_CONFIG=4ch_R2C_2x_250MHz_NCO_${nco_ghz}GHz_MTS_TRUE"

        # ---------------------------------------------------------------------
        # 4. Derive 125 MHz DOA clock & synchronous reset
        # ---------------------------------------------------------------------
        set doa_clk_mhz [expr {[info exists ::env(DOA_CLOCK_HZ)] ? [format "%.3f" [expr {double($::env(DOA_CLOCK_HZ)) / 1.0e6}]] : "125.000"}]
        set clk_doa_cell [doa_create_pinned_ip clk_wiz doa_clk_wiz_125m]
        set_property -dict [list \
            CONFIG.PRIM_SOURCE {No_buffer} \
            CONFIG.PRIM_IN_FREQ {250.000} \
            CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $doa_clk_mhz \
            CONFIG.USE_RESET {false} \
            CONFIG.USE_LOCKED {true} \
        ] $clk_doa_cell
        connect_bd_net $clk_rf_250m [::doa_bd_map::require_pin "$clk_doa_cell/clk_in1"]
        set clk_doa_125m [::doa_bd_map::require_pin "$clk_doa_cell/clk_out1"]

        set rst_doa_cell [doa_create_pinned_ip proc_sys_reset doa_rst_125m]
        connect_bd_net $clk_doa_125m [::doa_bd_map::require_pin "$rst_doa_cell/slowest_sync_clk"]
        connect_bd_net $pl_resetn0   [::doa_bd_map::require_pin "$rst_doa_cell/ext_reset_in"]
        connect_bd_net [::doa_bd_map::require_pin "$clk_doa_cell/locked"] [::doa_bd_map::require_pin "$rst_doa_cell/dcm_locked"]
        set rst_doa_125m_n [::doa_bd_map::require_pin "$rst_doa_cell/peripheral_aresetn"]

        connect_bd_net $clk_doa_125m   [::doa_bd_map::require_pin "/${hier}/aclk"]
        connect_bd_net $rst_doa_125m_n [::doa_bd_map::require_pin "/${hier}/aresetn"]
        ::doa_bd_map::log $fh "DOA_CLOCK_MHZ=$doa_clk_mhz"

        # ---------------------------------------------------------------------
        # 5. Wideband 250 MHz frontend: rfdc_repack4 -> 4x channelizer -> bridge
        # ---------------------------------------------------------------------
        set repack [doa_create_pinned_ip rfdc_repack4 doa_rfdc_repack_0]
        connect_bd_net $clk_rf_250m   [::doa_bd_map::require_pin "$repack/ap_clk"]
        connect_bd_net $rst_rf_250m_n [::doa_bd_map::require_pin "$repack/ap_rst_n"]

        foreach {ch_idx i_pin q_pin} {
            0 m00_axis m01_axis
            1 m02_axis m03_axis
            2 m10_axis m11_axis
            3 m12_axis m13_axis
        } {
            connect_bd_intf_net \
                [::doa_bd_map::require_intf_pin "$rfdc/$i_pin"] \
                [::doa_bd_map::require_intf_pin "$repack/s_axis_ch${ch_idx}_i"]
            connect_bd_intf_net \
                [::doa_bd_map::require_intf_pin "$rfdc/$q_pin"] \
                [::doa_bd_map::require_intf_pin "$repack/s_axis_ch${ch_idx}_q"]
        }

        set bridge [doa_create_pinned_ip subband_bridge doa_subband_bridge_0]
        connect_bd_net $clk_rf_250m   [::doa_bd_map::require_pin "$bridge/aclk"]
        connect_bd_net $rst_rf_250m_n [::doa_bd_map::require_pin "$bridge/aresetn"]

        for {set ch 0} {$ch < 4} {incr ch} {
            set chan_cell [doa_create_pinned_ip channelizer "doa_channelizer_${ch}"]
            connect_bd_net $clk_rf_250m   [::doa_bd_map::require_pin "$chan_cell/aclk"]
            connect_bd_net $rst_rf_250m_n [::doa_bd_map::require_pin "$chan_cell/aresetn"]
            connect_bd_intf_net \
                [::doa_bd_map::require_intf_pin "$repack/m_axis_ch${ch}"] \
                [::doa_bd_map::require_intf_pin "$chan_cell/s_axis"]
            connect_bd_intf_net \
                [::doa_bd_map::require_intf_pin "$chan_cell/m_axis"] \
                [::doa_bd_map::require_intf_pin "$bridge/s_axis_ch${ch}"]
        }

        # Tie legacy MTS capture hierarchies cleanly to bridge monitor streams
        connect_bd_intf_net [::doa_bd_map::require_intf_pin "$bridge/m_axis_mon_ch0"] [::doa_bd_map::require_intf_pin "$adc0_cap/S_AXIS"]
        connect_bd_intf_net [::doa_bd_map::require_intf_pin "$bridge/m_axis_mon_ch1"] [::doa_bd_map::require_intf_pin "$adc1_cap/S_AXIS"]
        connect_bd_intf_net [::doa_bd_map::require_intf_pin "$bridge/m_axis_mon_ch2"] [::doa_bd_map::require_intf_pin "$adc2_cap/S_AXIS"]
        connect_bd_intf_net [::doa_bd_map::require_intf_pin "$bridge/m_axis_mon_ch3"] [::doa_bd_map::require_intf_pin "$deep_cap/S_AXIS"]

        # ---------------------------------------------------------------------
        # 6. 250 MHz <-> 125 MHz AXI4-Stream asynchronous CDCs
        # ---------------------------------------------------------------------
        foreach {cdc_name src_pin dst_pin} [list \
            doa_cdc_search  "$bridge/m_axis_search"  "/${hier}/S_AXIS_SEARCH" \
            doa_cdc_capture "$bridge/m_axis_capture" "/${hier}/S_AXIS_DOA_CAPTURE" \
            doa_cdc_beam    "$bridge/m_axis_beam"    "/${hier}/S_AXIS_BEAM_MONITOR" \
        ] {
            set cdc [doa_create_pinned_ip axis_clock_converter $cdc_name]
            set_property CONFIG.IS_ACLK_ASYNC {1} $cdc
            connect_bd_net $clk_rf_250m    [::doa_bd_map::require_pin "$cdc/s_axis_aclk"]
            connect_bd_net $rst_rf_250m_n  [::doa_bd_map::require_pin "$cdc/s_axis_aresetn"]
            connect_bd_net $clk_doa_125m   [::doa_bd_map::require_pin "$cdc/m_axis_aclk"]
            connect_bd_net $rst_doa_125m_n [::doa_bd_map::require_pin "$cdc/m_axis_aresetn"]
            connect_bd_intf_net [::doa_bd_map::require_intf_pin $src_pin] [::doa_bd_map::require_intf_pin "$cdc/S_AXIS"]
            connect_bd_intf_net [::doa_bd_map::require_intf_pin "$cdc/M_AXIS"] [::doa_bd_map::require_intf_pin $dst_pin]
        }

        set cdc_cand [doa_create_pinned_ip axis_clock_converter doa_cdc_candidate]
        set_property CONFIG.IS_ACLK_ASYNC {1} $cdc_cand
        connect_bd_net $clk_doa_125m   [::doa_bd_map::require_pin "$cdc_cand/s_axis_aclk"]
        connect_bd_net $rst_doa_125m_n [::doa_bd_map::require_pin "$cdc_cand/s_axis_aresetn"]
        connect_bd_net $clk_rf_250m    [::doa_bd_map::require_pin "$cdc_cand/m_axis_aclk"]
        connect_bd_net $rst_rf_250m_n  [::doa_bd_map::require_pin "$cdc_cand/m_axis_aresetn"]
        connect_bd_intf_net [::doa_bd_map::require_intf_pin "/${hier}/M_AXIS_CANDIDATE"] [::doa_bd_map::require_intf_pin "$cdc_cand/S_AXIS"]
        connect_bd_intf_net [::doa_bd_map::require_intf_pin "$cdc_cand/M_AXIS"] [::doa_bd_map::require_intf_pin "$bridge/s_axis_candidate"]

        # ---------------------------------------------------------------------
        # 7. PS-accessible AXI4-Stream RX FIFOs for M_AXIS_COVARIANCE & M_AXIS_BEAM
        # ---------------------------------------------------------------------
        foreach {src_pin dwc_name fifo_name rx_depth} [list \
            "/${hier}/M_AXIS_COVARIANCE" doa_cov_dwc  doa_cov_fifo  512 \
            "/${hier}/M_AXIS_BEAM"       doa_beam_dwc doa_beam_fifo 2048 \
        ] {
            set dwc [doa_create_pinned_ip axis_dwidth_converter $dwc_name]
            set_property CONFIG.M_TDATA_NUM_BYTES {4} $dwc
            connect_bd_net $clk_doa_125m   [::doa_bd_map::require_pin "$dwc/aclk"]
            connect_bd_net $rst_doa_125m_n [::doa_bd_map::require_pin "$dwc/aresetn"]

            set fifo [doa_create_pinned_ip axi_fifo_mm_s $fifo_name]
            set_property -dict [list \
                CONFIG.C_DATA_INTERFACE_TYPE {0} \
                CONFIG.C_USE_TX_DATA {0} \
                CONFIG.C_USE_TX_CTRL {0} \
                CONFIG.C_USE_RX_DATA {1} \
                CONFIG.C_RX_FIFO_DEPTH $rx_depth \
            ] $fifo
            connect_bd_net $clk_doa_125m   [::doa_bd_map::require_pin "$fifo/s_axi_aclk"]
            connect_bd_net $rst_doa_125m_n [::doa_bd_map::require_pin "$fifo/s_axi_aresetn"]

            set fifo_rx_axis [get_bd_intf_pins -of_objects $fifo -filter {VLNV == "xilinx.com:interface:axis_rtl:1.0" && MODE == "Slave"}]
            if {[llength $fifo_rx_axis] != 1} {
                error "Expected 1 Slave AXIS pin on $fifo, found: $fifo_rx_axis"
            }
            connect_bd_intf_net [::doa_bd_map::require_intf_pin $src_pin] [::doa_bd_map::require_intf_pin "$dwc/S_AXIS"]
            connect_bd_intf_net [::doa_bd_map::require_intf_pin "$dwc/M_AXIS"] [lindex $fifo_rx_axis 0]
        }

        # ---------------------------------------------------------------------
        # 8. Attach all 6 DOA AXI4-Lite slaves to /control_interconnect (M07..M12)
        # ---------------------------------------------------------------------
        set_property CONFIG.NUM_MI {13} $ctrl_ic

        foreach {mi_idx slave_intf clk_pin rst_pin} [list \
            07 "/${hier}/S_AXI_COV_CTRL"       $clk_doa_125m $rst_doa_125m_n \
            08 "/${hier}/S_AXI_CANDIDATE_CTRL" $clk_doa_125m $rst_doa_125m_n \
            09 "/${hier}/S_AXI_BEAM_CTRL"      $clk_doa_125m $rst_doa_125m_n \
            10 "/doa_cov_fifo/S_AXI"           $clk_doa_125m $rst_doa_125m_n \
            11 "/doa_beam_fifo/S_AXI"          $clk_doa_125m $rst_doa_125m_n \
            12 "/doa_subband_bridge_0/s_axi_ctrl" $clk_rf_250m $rst_rf_250m_n \
        ] {
            ::doa_bd_map::disconnect_intf_pin "$ctrl_ic/M${mi_idx}_AXI"
            ::doa_bd_map::rewire_scalar_pin "$ctrl_ic/M${mi_idx}_ACLK"    $clk_pin
            ::doa_bd_map::rewire_scalar_pin "$ctrl_ic/M${mi_idx}_ARESETN" $rst_pin
            connect_bd_intf_net \
                [::doa_bd_map::require_intf_pin "$ctrl_ic/M${mi_idx}_AXI"] \
                [::doa_bd_map::require_intf_pin $slave_intf]
        }

        ::doa_bd_map::log $fh "CONTROL_INTERCONNECT_MI=M07..M12_CONNECTED"
        ::doa_bd_map::log $fh "V07 BD INTEGRATION RESULT=PASS"
    } err_msg err_opts]

    current_bd_instance $saved_inst
    if {$rc != 0} {
        ::doa_bd_map::log $fh "ERROR=$err_msg"
        ::doa_bd_map::log $fh "V07 BD INTEGRATION RESULT=FAIL"
        close $fh
        return -options $err_opts $err_msg
    }
    close $fh
}
