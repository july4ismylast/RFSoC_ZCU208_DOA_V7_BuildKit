# config/ip_versions.tcl
# -----------------------------------------------------------------------------
# SINGLE SOURCE OF TRUTH for every Vivado / IP version used by this project.
#
# Project rule (V00): first check the IP/Vivado version, put it in a variable
# here, and only then use that variable in all later Tcl.  No "*" VLNVs and no
# "pick the last/latest IP" logic are allowed in production Tcl.
#
# Lock decision (2026-11-01, user-confirmed):
#   Vivado / Vitis HLS ........... 2023.2
#   Base project ................. Xilinx RFSoC-MTS, boards/ZCU208 (git)
#   Target RF band ............... 2-4 GHz
#   ADC channels ................. 4
#
# How this table was filled: VLNVs extracted from the actual block-design Tcl
# of RFSoC-MTS (2022.1.2), RFSoC-PYNQ (2022.1 / 2024.1 / 2025.2), rfsoc_sam
# (2024.1), RFSoC_OPFB (2022.1), rfsoc4x2_public (2022.1) and SPEAR* (2021.1),
# then moved to the 2023.2 catalog.  The two version-sensitive entries are
# confirmed by AMD's 2023.2 Vivado IP Release Notes (Answer Record 000035673):
# Zynq UltraScale+ MPSoC Processing System = 3.5 and RF Data Converter = 2.6
# (3.5 was introduced in 2023.1; MTS still carries 3.4, hence the controlled
# IP upgrade in stage V03).  All other catalog IPs below are unchanged across
# 2022.1 -> 2024.1 in the audited designs.
#
# IMPORTANT: this file is a *claim* until step00 proves it on the build PC.
# `make step00_preflight` runs common/vivado/00_check_ip_catalog.tcl, which
# asks the installed Vivado 2023.2 for every VLNV below and fails with the
# list of actually-available versions if any entry is wrong.  If that happens,
# fix the one line here -- nowhere else.
# -----------------------------------------------------------------------------

namespace eval ::doa_versions {}

proc ::doa_versions::env_or {name default_value} {
    if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
        return [string trim $::env($name)]
    }
    return $default_value
}

# --- Tool / board lock --------------------------------------------------------
# The VLNV table below is certified only for this Vivado release.
set ::VIVADO_LOCK_CERTIFIED "2023.2"
set ::VIVADO_LOCK_VERSION [::doa_versions::env_or EXPECTED_VIVADO_VERSION $::VIVADO_LOCK_CERTIFIED]
set ::PART_PINNED         [::doa_versions::env_or PART "xczu48dr-fsvg1517-2-e"]
set ::BOARD_PART_PINNED   [::doa_versions::env_or BOARD_PART "xilinx.com:zcu208:part0:2.0"]
set ::BASE_KIND_PINNED    [::doa_versions::env_or BASE_KIND "mts"]

# --- Custom-IP identity (mirrored in config.mk; HLS reads it from the env) ----
set ::CUSTOM_IP_VENDOR  [::doa_versions::env_or CUSTOM_IP_VENDOR  "openai"]
set ::CUSTOM_IP_LIBRARY [::doa_versions::env_or CUSTOM_IP_LIBRARY "doa"]
set ::IPVER_COVARIANCE  [::doa_versions::env_or IPVER_COVARIANCE  "7.1"]
set ::IPVER_SPECTRUM    [::doa_versions::env_or IPVER_SPECTRUM    "2.0"]
set ::IPVER_CANDIDATE   [::doa_versions::env_or IPVER_CANDIDATE   "1.0"]
set ::IPVER_BEAM        [::doa_versions::env_or IPVER_BEAM        "2.1"]
set ::IPVER_RFDC_REPACK4   [::doa_versions::env_or IPVER_RFDC_REPACK4   "1.0"]
set ::IPVER_CHANNELIZER    [::doa_versions::env_or IPVER_CHANNELIZER    "7.0"]
set ::IPVER_SUBBAND_BRIDGE [::doa_versions::env_or IPVER_SUBBAND_BRIDGE "1.0"]
set ::IPVER_PHASE_INTERF   [::doa_versions::env_or IPVER_PHASE_INTERF   "1.0"]

# --- AMD catalog IP for Vivado 2023.2 -----------------------------------------
# Key naming: short role name used by doa_pinned_ip / doa_create_pinned_ip.
# Entries marked (V04/V07) are not instantiated yet; they are pinned now so
# the RFDC reconfiguration and BD-map stages cannot drift to a wildcard.
set ::IPVLNV(rfdc)                 "xilinx.com:ip:usp_rf_data_converter:2.6"
set ::IPVLNV(ps)                   "xilinx.com:ip:zynq_ultra_ps_e:3.5"
set ::IPVLNV(axis_data_fifo)       "xilinx.com:ip:axis_data_fifo:2.0"
set ::IPVLNV(axi_data_fifo)        "xilinx.com:ip:axi_data_fifo:2.1"
set ::IPVLNV(axi_fifo_mm_s)        "xilinx.com:ip:axi_fifo_mm_s:4.3"
set ::IPVLNV(axi_bram_ctrl)        "xilinx.com:ip:axi_bram_ctrl:4.1"
set ::IPVLNV(blk_mem_gen)          "xilinx.com:ip:blk_mem_gen:8.4"
set ::IPVLNV(axi_dma)              "xilinx.com:ip:axi_dma:7.1"
set ::IPVLNV(axi_datamover)        "xilinx.com:ip:axi_datamover:5.1"
set ::IPVLNV(axi_interconnect)     "xilinx.com:ip:axi_interconnect:2.1"
set ::IPVLNV(smartconnect)         "xilinx.com:ip:smartconnect:1.0"
set ::IPVLNV(axi_clock_converter)  "xilinx.com:ip:axi_clock_converter:2.1"
set ::IPVLNV(axi_dwidth_converter) "xilinx.com:ip:axi_dwidth_converter:2.1"
set ::IPVLNV(axi_register_slice)   "xilinx.com:ip:axi_register_slice:2.1"
set ::IPVLNV(axi_gpio)             "xilinx.com:ip:axi_gpio:2.0"
set ::IPVLNV(axi_intc)             "xilinx.com:ip:axi_intc:4.1"
set ::IPVLNV(proc_sys_reset)       "xilinx.com:ip:proc_sys_reset:5.0"
set ::IPVLNV(clk_wiz)              "xilinx.com:ip:clk_wiz:6.0"
set ::IPVLNV(ddr4)                 "xilinx.com:ip:ddr4:2.2"
set ::IPVLNV(axis_clock_converter)   "xilinx.com:ip:axis_clock_converter:1.1"
set ::IPVLNV(axis_dwidth_converter)  "xilinx.com:ip:axis_dwidth_converter:1.1"
set ::IPVLNV(axis_register_slice)    "xilinx.com:ip:axis_register_slice:1.1"
set ::IPVLNV(axis_broadcaster)       "xilinx.com:ip:axis_broadcaster:1.1"
set ::IPVLNV(axis_combiner)          "xilinx.com:ip:axis_combiner:1.1"
set ::IPVLNV(axis_switch)            "xilinx.com:ip:axis_switch:1.1"
set ::IPVLNV(fir_compiler)           "xilinx.com:ip:fir_compiler:7.2"
set ::IPVLNV(util_ds_buf)            "xilinx.com:ip:util_ds_buf:2.2"
set ::IPVLNV(xpm_cdc_gen)            "xilinx.com:ip:xpm_cdc_gen:1.0"
set ::IPVLNV(xlconcat)               "xilinx.com:ip:xlconcat:2.1"
set ::IPVLNV(xlconstant)             "xilinx.com:ip:xlconstant:1.1"
set ::IPVLNV(xlslice)                "xilinx.com:ip:xlslice:1.0"
set ::IPVLNV(util_reduced_logic)     "xilinx.com:ip:util_reduced_logic:2.0"
set ::IPVLNV(util_vector_logic)      "xilinx.com:ip:util_vector_logic:2.0"
set ::IPVLNV(ila)                    "xilinx.com:ip:ila:6.2"
set ::IPVLNV(vio)                    "xilinx.com:ip:vio:3.0"

# --- This project's custom IP (built by step02-step05 into build/ip_repo) -----
set ::IPVLNV(covariance) "$::CUSTOM_IP_VENDOR:$::CUSTOM_IP_LIBRARY:doa_covariance_4ch_v4:$::IPVER_COVARIANCE"
set ::IPVLNV(spectrum)   "$::CUSTOM_IP_VENDOR:$::CUSTOM_IP_LIBRARY:spectrum_power4:$::IPVER_SPECTRUM"
set ::IPVLNV(candidate)  "$::CUSTOM_IP_VENDOR:$::CUSTOM_IP_LIBRARY:candidate_peak4:$::IPVER_CANDIDATE"
set ::IPVLNV(beam)       "$::CUSTOM_IP_VENDOR:$::CUSTOM_IP_LIBRARY:beam_weight_4ch:$::IPVER_BEAM"
set ::IPVLNV(rfdc_repack4)   "$::CUSTOM_IP_VENDOR:$::CUSTOM_IP_LIBRARY:rfdc_repack4:$::IPVER_RFDC_REPACK4"
set ::IPVLNV(channelizer)    "$::CUSTOM_IP_VENDOR:$::CUSTOM_IP_LIBRARY:matlab_channelizer:$::IPVER_CHANNELIZER"
set ::IPVLNV(subband_bridge) "$::CUSTOM_IP_VENDOR:$::CUSTOM_IP_LIBRARY:doa_subband_bridge_4ch:$::IPVER_SUBBAND_BRIDGE"
# V07 per-bin phase interferometer (cross-spectrum + CORDIC phase):
set ::IPVLNV(phase_interf)   "$::CUSTOM_IP_VENDOR:$::CUSTOM_IP_LIBRARY:phase_interf_4ch:$::IPVER_PHASE_INTERF"

# Keys that must exist in the *installed AMD catalog* at step00 (custom IP is
# verified later, at step06/step08, after build/ip_repo is on the IP path).
set ::IP_CATALOG_KEYS {
    rfdc ps axis_data_fifo axi_data_fifo axi_fifo_mm_s axi_bram_ctrl
    blk_mem_gen axi_dma axi_datamover axi_interconnect smartconnect
    axi_clock_converter axi_dwidth_converter axi_register_slice axi_gpio
    axi_intc proc_sys_reset clk_wiz ddr4 axis_clock_converter
    axis_dwidth_converter axis_register_slice axis_broadcaster axis_combiner
    axis_switch fir_compiler util_ds_buf xpm_cdc_gen xlconcat xlconstant
    xlslice util_reduced_logic util_vector_logic ila vio
}
set ::IP_CUSTOM_KEYS {covariance spectrum candidate beam rfdc_repack4 channelizer subband_bridge phase_interf}

# -----------------------------------------------------------------------------
# Procedures.  They call Vivado-only commands (version, get_ipdefs,
# create_bd_cell) and are therefore only *invoked* inside Vivado; sourcing this
# file in plain tclsh (make lint) is safe.
# -----------------------------------------------------------------------------

# Borrowed pattern: the version guard at the top of every Vivado-generated
# block-design Tcl (rfsoc_sam / RFSoC-PYNQ base.tcl, lines ~21-42), tightened
# to also reject a lock request this VLNV table is not certified for.
proc doa_require_vivado_lock {} {
    if {$::VIVADO_LOCK_VERSION ne $::VIVADO_LOCK_CERTIFIED} {
        error "Vivado lock: config/ip_versions.tcl is certified only for \
$::VIVADO_LOCK_CERTIFIED, but EXPECTED_VIVADO_VERSION=$::VIVADO_LOCK_VERSION. \
Re-verify every VLNV in this file for that release before changing the lock."
    }
    set running [version -short]
    if {[string first $::VIVADO_LOCK_VERSION $running] == -1} {
        error "Vivado lock: need Vivado $::VIVADO_LOCK_VERSION, running $running. \
Do not let another Vivado release open/upgrade this project.  If an upgrade \
is intended, follow the BD-Tcl guard procedure: run the design in \
$::VIVADO_LOCK_VERSION, open it in the new release, use Report IP Status to \
upgrade, then write_bd_tcl and re-certify config/ip_versions.tcl."
    }
    puts "DOA version lock OK: Vivado $running, part $::PART_PINNED, board $::BOARD_PART_PINNED"
}

# Return the pinned VLNV string for a key directly from config/ip_versions.tcl
# without requiring an open Vivado project (used by IP packaging and XML checks).
proc doa_vlnv {key} {
    if {![info exists ::IPVLNV($key)]} {
        error "Unknown IP key '$key'.  Add its pinned VLNV to config/ip_versions.tcl first."
    }
    return $::IPVLNV($key)
}

# Return the exact VLNV for a key, proving that exactly one such IP definition
# is visible.  Replaces the old find_unique_ipdef (which took the last sorted
# NAME match, ignoring version) and every "xilinx.com:ip:<name>:*" wildcard.
proc doa_pinned_ip {key} {
    if {![info exists ::IPVLNV($key)]} {
        error "Unknown IP key '$key'.  Add its pinned VLNV to config/ip_versions.tcl first."
    }
    set vlnv $::IPVLNV($key)
    set defs [get_ipdefs -all -filter "VLNV == $vlnv"]
    if {[llength $defs] != 1} {
        set ip_name [lindex [split $vlnv :] 2]
        set available [get_ipdefs -all -filter "NAME == $ip_name"]
        error "Pinned IP for key '$key' not found exactly once: $vlnv \
(found [llength $defs]).  Available definitions for NAME=$ip_name: $available. \
Fix config/ip_versions.tcl (one line) or rebuild the custom IP -- do not \
fall back to a wildcard."
    }
    return $vlnv
}

# Convenience wrapper used from block-design Tcl:
#   set fifo [doa_create_pinned_ip axis_data_fifo covariance_fifo]
proc doa_create_pinned_ip {key instance} {
    return [create_bd_cell -type ip -vlnv [doa_pinned_ip $key] $instance]
}
