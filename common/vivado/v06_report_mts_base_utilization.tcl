# Stage V06 resource-budget evidence (read-only): report the actual
# routed utilization of the unmodified V03 RFSoC-MTS ZCU208 base.
#
# Gate 2T proved that one transposed channelizer is much smaller in
# LUTs than the systolic baseline, but four transposed channels use
# 704 Block RAM Tiles.  Before selecting that architecture for V07 we
# therefore need the real MTS-base LUT/FF/BRAM/URAM/DSP usage, not a
# grep fragment from a synthesis report.
#
# This script opens the existing routed checkpoint in memory, writes
# detailed + hierarchical utilization reports, parses the key rows,
# and also records a crude "routed MTS base + 4x Gate-2T channelizer"
# sum.  That sum is deliberately labelled crude: V07 will remove or
# replace parts of the MTS capture path and must still add V05,
# snapshot serialization, control/DMA and DOA logic.
#
# Run from the repo root:
#   vivado -mode batch -nojournal -nolog \
#       -source common/vivado/v06_report_mts_base_utilization.tcl
#
# Optional environment overrides:
#   MTS_ROUTED_DCP  explicit routed checkpoint
#   BASE_XPR        derive <project-dir>/mts.runs/impl_1/... from it
#   BUILD           build root (default <repo>/build)

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir .. ..]]
source [file join $root_dir config ip_versions.tcl]
doa_require_vivado_lock

proc env_or {name default_value} {
    if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
        return [string trim $::env($name)]
    }
    return $default_value
}

proc log_line {fh message} {
    puts $message
    puts $fh $message
    flush $fh
}

proc read_text_file {path} {
    set fh [open $path r]
    set data [read $fh]
    close $fh
    return $data
}

proc parse_utilization {text label} {
    foreach raw_line [split $text "\n"] {
        set line [string trimright $raw_line "\r"]
        if {[string first "|" $line] < 0} {
            continue
        }
        set cells {}
        foreach cell [split $line "|"] {
            set cell [string trim $cell]
            if {$cell ne ""} {
                lappend cells $cell
            }
        }
        if {[llength $cells] < 4} {
            continue
        }
        # Vivado can mark a row with a footnote asterisk, for example
        # "CLB LUTs*".  Compare the cleaned first cell rather than
        # matching padded raw table text.
        set row_label [string trimright [lindex $cells 0] "* "]
        if {$row_label eq $label} {
            return [list [lindex $cells 1] [lindex $cells end-1] \
                [lindex $cells end]]
        }
    }
    return {}
}

proc parse_utilization_used {text label} {
    foreach raw_line [split $text "\n"] {
        set line [string trimright $raw_line "\r"]
        if {[string first "|" $line] < 0} {
            continue
        }
        set cells {}
        foreach cell [split $line "|"] {
            set cell [string trim $cell]
            if {$cell ne ""} {
                lappend cells $cell
            }
        }
        if {[llength $cells] < 2} {
            continue
        }
        set row_label [string trimright [lindex $cells 0] "* "]
        if {$row_label eq $label} {
            return [lindex $cells 1]
        }
    }
    return {}
}

set build_root [file normalize [env_or BUILD [file join $root_dir build]]]
set output_dir [file join $build_root output]
file mkdir $output_dir

set summary_file [file join $output_dir v06_mts_base_utilization.rpt]
set detailed_file [file join $output_dir \
    v06_mts_base_utilization_detailed.rpt]
set hierarchical_file [file join $output_dir \
    v06_mts_base_utilization_hierarchical.rpt]

set explicit_dcp [env_or MTS_ROUTED_DCP ""]
set base_xpr [env_or BASE_XPR ""]
if {$explicit_dcp ne ""} {
    set routed_dcp [file normalize $explicit_dcp]
} elseif {$base_xpr ne ""} {
    set routed_dcp [file normalize [file join \
        [file dirname [file normalize $base_xpr]] mts.runs impl_1 \
        mts_wrapper_routed.dcp]]
} else {
    set routed_dcp [file normalize [file join $build_root \
        mts_base_src_2023p2 boards ZCU208 build_mts mts mts.runs impl_1 \
        mts_wrapper_routed.dcp]]
}
if {![file exists $routed_dcp]} {
    set impl_dir [file dirname $routed_dcp]
    set routed_candidates [glob -nocomplain -directory $impl_dir \
        *routed*.dcp]
    if {[llength $routed_candidates] == 1} {
        set routed_dcp [file normalize [lindex $routed_candidates 0]]
    } elseif {[llength $routed_candidates] > 1} {
        error "Multiple routed checkpoints found in $impl_dir: $routed_candidates. Set MTS_ROUTED_DCP explicitly."
    }
}

set summary_fh [open $summary_file w]
log_line $summary_fh "# V06 MTS-base routed utilization, read-only"
log_line $summary_fh "SCRIPT_REVISION=1-gate2t-budget"
log_line $summary_fh "VIVADO_VERSION=[version -short]"
log_line $summary_fh "EXPECTED_PART=$::PART_PINNED"
log_line $summary_fh "BOARD_PART_CONTEXT=$::BOARD_PART_PINNED"
log_line $summary_fh "BUILD_ROOT=$build_root"
log_line $summary_fh "ROUTED_DCP=$routed_dcp"
log_line $summary_fh "REPORT=$summary_file"
log_line $summary_fh "UTILIZATION_REPORT=$detailed_file"
log_line $summary_fh "UTILIZATION_HIERARCHICAL_REPORT=$hierarchical_file"

set gate_status "PASS"
set gate_error ""
set catch_rc [catch {
    if {![file exists $routed_dcp]} {
        error "Routed MTS checkpoint not found: $routed_dcp. Do not rebuild blindly; set MTS_ROUTED_DCP to the final V03 routed checkpoint if it has a different name."
    }

    open_checkpoint $routed_dcp
    log_line $summary_fh "CHECKPOINT_OPENED=1"
    set design_part ""
    if {[catch {get_property PART [current_design]} design_part]} {
        set design_part ""
    }
    log_line $summary_fh "DESIGN_PART=$design_part"
    if {$design_part ne "" && $design_part ne $::PART_PINNED} {
        error "Routed checkpoint part '$design_part' != pinned '$::PART_PINNED'"
    }

    report_utilization -file $detailed_file
    report_utilization -hierarchical -hierarchical_depth 4 \
        -file $hierarchical_file
    close_design
    log_line $summary_fh "UTILIZATION_REPORTS_WRITTEN=1"

    set utilization_text [read_text_file $detailed_file]
    set resource_specs {
        {CLB_LUTS "CLB LUTs"}
        {CLB_REGISTERS "CLB Registers"}
        {BLOCK_RAM_TILE "Block RAM Tile"}
        {URAM "URAM"}
        {DSPS "DSPs"}
    }
    # Proved one-channel Gate-2T values from
    # build/output/v06_gate2t_transposed_ooc_synthesis.rpt
    # (user PC, Vivado 2023.2, 2026-11-03).
    array set gate2t_one {
        CLB_LUTS 35902
        CLB_REGISTERS 58626
        BLOCK_RAM_TILE 176
        URAM 0
        DSPS 312
    }
    array set mts_used {}
    array set mts_available {}
    foreach resource_spec $resource_specs {
        set resource_key [lindex $resource_spec 0]
        set resource_label [lindex $resource_spec 1]
        set resource_values [parse_utilization $utilization_text \
            $resource_label]
        if {[llength $resource_values] != 3} {
            error "Could not parse utilization row '$resource_label' from $detailed_file"
        }
        set used [lindex $resource_values 0]
        set available [lindex $resource_values 1]
        set percent [lindex $resource_values 2]
        if {![string is double -strict $used] || \
                ![string is double -strict $available]} {
            error "Non-numeric utilization for $resource_label: used=$used available=$available"
        }
        set mts_used($resource_key) $used
        set mts_available($resource_key) $available
        log_line $summary_fh "MTS_${resource_key}_USED=$used"
        log_line $summary_fh "MTS_${resource_key}_AVAILABLE=$available"
        log_line $summary_fh "MTS_${resource_key}_PERCENT=$percent"
    }

    set detail_specs {
        {LUT_AS_LOGIC "LUT as Logic"}
        {LUT_AS_MEMORY "LUT as Memory"}
        {LUT_AS_DISTRIBUTED_RAM "LUT as Distributed RAM"}
        {LUT_AS_SHIFT_REGISTER "LUT as Shift Register"}
        {RAMB36_FIFO "RAMB36/FIFO"}
        {RAMB18 "RAMB18"}
    }
    foreach detail_spec $detail_specs {
        set detail_key [lindex $detail_spec 0]
        set detail_label [lindex $detail_spec 1]
        set detail_used [parse_utilization_used $utilization_text \
            $detail_label]
        if {$detail_used eq "" || \
                ![string is double -strict $detail_used]} {
            error "Could not parse detail utilization row '$detail_label' from $detailed_file"
        }
        log_line $summary_fh "MTS_${detail_key}_USED=$detail_used"
    }

    set crude_exceeds {}
    foreach resource_spec $resource_specs {
        set resource_key [lindex $resource_spec 0]
        set available $mts_available($resource_key)
        set x4_gate2t [expr {4.0 * $gate2t_one($resource_key)}]
        set crude_total [expr {$mts_used($resource_key) + $x4_gate2t}]
        set crude_percent "NA"
        set crude_remaining "NA"
        if {$available > 0} {
            set crude_percent [format %.4f \
                [expr {100.0 * $crude_total / $available}]]
            set crude_remaining [format %.3f \
                [expr {$available - $crude_total}]]
        }
        log_line $summary_fh \
            "GATE2T_ONE_${resource_key}_USED=$gate2t_one($resource_key)"
        log_line $summary_fh \
            "GATE2T_X4_${resource_key}_USED=[format %.3f $x4_gate2t]"
        log_line $summary_fh \
            "CRUDE_MTS_PLUS_X4_GATE2T_${resource_key}_USED=[format %.3f $crude_total]"
        log_line $summary_fh \
            "CRUDE_MTS_PLUS_X4_GATE2T_${resource_key}_PERCENT=$crude_percent"
        log_line $summary_fh \
            "CRUDE_MTS_PLUS_X4_GATE2T_${resource_key}_REMAINING=$crude_remaining"
        if {$available > 0 && $crude_total > $available} {
            lappend crude_exceeds $resource_key
        }
    }
    if {[llength $crude_exceeds] == 0} {
        log_line $summary_fh "CRUDE_MTS_PLUS_X4_GATE2T_EXCEEDS_PART=NONE"
    } else {
        log_line $summary_fh \
            "CRUDE_MTS_PLUS_X4_GATE2T_EXCEEDS_PART=[join $crude_exceeds ,]"
    }
    log_line $summary_fh "RESOURCE_REVIEW_REQUIRED=1"
    log_line $summary_fh "IMPLEMENTATION_PERFORMED=0"
    log_line $summary_fh "PROJECT_SAVED=0"
} gate_error]

if {$catch_rc != 0} {
    set gate_status "FAIL"
    log_line $summary_fh "ERROR_MESSAGE=$gate_error"
}
log_line $summary_fh "V06 MTS BASE UTILIZATION RESULT=$gate_status"
close $summary_fh

if {$gate_status ne "PASS"} {
    error "V06 MTS base utilization report failed: $gate_error"
}
puts "V06 MTS base utilization PASS: $summary_file"
