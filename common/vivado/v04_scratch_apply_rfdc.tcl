# Stage V04: SCRATCH-ONLY RFDC R2C apply + readback proof.
#
# Safety contract:
#   * Input is the step07 work project (WORK_XPR).  It is copied with
#     save_project_as into a separate scratch project; every modification
#     and the only save_bd_design happen in that scratch copy.  The input
#     project/BD and the V03 MTS base are never written by this script.
#   * This proves exactly one thing: Vivado 2023.2 accepts the candidate
#     RFDC CONFIG diff, the odd Q streams appear, and the values persist
#     on reopen.  It does NOT rewire clocks or streams: in the scratch BD
#     m0/m1_axis_aclk are still on the 500 MHz MTS clock and the old
#     500 MHz capture hierarchies are still attached, so the separate
#     validate_bd_design result is reported but is not the pass gate.
#     Production clock/stream rewiring is stage V07.
#
# Candidate values (all XML-proven on the user PC, 2026-11-03, from the
# RFDC 2.6 component.xml choices; see V04_RFDC_DOA_CONTRACT.md section 3):
#   Data_Type I/Q=1 | Decimation 2x=2 | Mixer_Mode Real->I/Q=0 |
#   Mixer_Type Fine=2 | Data_Width=8 | NCO_Freq=-3.0 GHz | NCO_Phase=0 |
#   Nyquist Zone 2=1 | CalOpt Mode2=1 | ADC0/1_Fabric_Freq=250.000 MHz
# Written to pair indices 00/02/10/12 (upstream SAM pattern); all eight
# slices are read back (first run proved Vivado propagates pair-head
# writes to the odd Q legs).
#
# v1.1 (after first user-PC run, 2026-11-03): properties are applied in
# staged atomic set_property -dict transactions, NOT one-by-one.  v1.0's
# individual Decimation_Mode writes were rejected while every other
# value succeeded: all converters in a tile share one fabric clock
# (PG269 System Clocking), so changing one pair to 2x (250 MHz) while
# its tile partner is still 1x (500 MHz) is transiently illegal.  The
# rate dict therefore changes every pair in the tile(s) together, with
# per-tile and final retries; failures now also log ::errorInfo so the
# real IP_Flow reason (hidden behind [Common 17-39]) reaches the report.
#
# v1.2 (after second user-PC run, 2026-11-03): v1.1 proved the datapath
# transaction (Decimation_Mode=2 on all slices, Fabric_Freq=250.000
# persisted, full-BD validate PASS), but ADC0/1_Multi_Tile_Sync silently
# changed true->false and v1.1 did not assert it.  MTS is mandatory for
# deterministic inter-tile latency/NCO alignment in this DOA design, so
# that result is only a partial pass.  v1.2 captures the before-state
# tile invariants, checkpoints ADC/DAC MTS after every stage, skips the
# direct Fabric_Freq write when Vivado has already computed 250, tries
# to re-enable MTS as a late transaction if the RFDC dependency
# logic cleared it, and hard-asserts MTS plus the captured invariants
# on the persisted readback.
#
# Usage (from the repo root, after step07):
#   vivado -mode batch -nojournal -nolog -source common/vivado/v04_scratch_apply_rfdc.tcl
# Env overrides: WORK_XPR, V04_SCRATCH_DIR, V04_SCRATCH_NAME.
# Report: build/output/v04_rfdc_scratch_apply.rpt
# Scratch project: build/vivado/v04_rfdc_scratch/doa_v7_zcu208_v04scratch.xpr
# (deletable at any time; nothing downstream consumes it).

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ../..]]
cd $repo_root

if {[info exists ::env(WORK_XPR)]} {
    set input_xpr [file normalize $::env(WORK_XPR)]
} else {
    set input_xpr [file normalize [file join $repo_root build \
        vivado doa_v7_zcu208 doa_v7_zcu208.xpr]]
}
if {[info exists ::env(V04_SCRATCH_DIR)]} {
    set scratch_dir [file normalize $::env(V04_SCRATCH_DIR)]
} else {
    set scratch_dir [file normalize [file join $repo_root build \
        vivado v04_rfdc_scratch]]
}
if {[info exists ::env(V04_SCRATCH_NAME)]} {
    set scratch_name [string trim $::env(V04_SCRATCH_NAME)]
} else {
    set scratch_name "doa_v7_zcu208_v04scratch"
}
if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $scratch_name]} {
    error "V04 scratch: invalid project name '$scratch_name'"
}
set scratch_xpr [file normalize [file join $scratch_dir ${scratch_name}.xpr]]
if {$scratch_xpr eq $input_xpr || $scratch_dir eq [file dirname $input_xpr]} {
    error "V04 scratch: scratch project would collide with the input project ($input_xpr); refusing to run"
}
if {![file exists $input_xpr]} {
    error "V04 scratch: input work project not found: $input_xpr (run step07 first)"
}

source [file join $repo_root config ip_versions.tcl]
doa_require_vivado_lock

set out_dir [file join $repo_root build output]
file mkdir $out_dir
set out_file [file join $out_dir v04_rfdc_scratch_apply.rpt]
set fh [open $out_file w]

proc v04a_log {fh msg} {
    puts $fh $msg
    flush $fh
    puts $msg
}

proc v04a_get {prop object} {
    if {[catch {set value [get_property $prop $object]}]} { return "<unavailable>" }
    return $value
}

proc v04a_num_eq {a b} {
    if {[catch {expr {abs(double($a) - double($b))}} delta]} { return 0 }
    return [expr {$delta < 1e-9}]
}

proc v04a_errinfo {} {
    if {![info exists ::errorInfo]} { return "" }
    set info [string trim $::errorInfo]
    if {[string length $info] > 2000} {
        set info "[string range $info 0 1999] ...<clipped>"
    }
    return $info
}

proc v04a_set {fh rfdc prop value required failures_var} {
    upvar $failures_var failures
    if {[catch {set_property $prop $value $rfdc} err]} {
        v04a_log $fh "SET ERROR $prop <- {$value}: $err"
        set info [v04a_errinfo]
        if {$info ne "" && $info ne $err} { v04a_log $fh "  errorInfo: $info" }
        if {$required} { lappend failures "set_property $prop failed: $err" }
        return 0
    }
    v04a_log $fh "SET $prop = {$value} (immediate readback {[v04a_get $prop $rfdc]})"
    return 1
}

proc v04a_build_dict {groups ids} {
    set propdict {}
    foreach group $groups {
        lassign $group prefix value
        foreach xx $ids {
            lappend propdict "CONFIG.ADC_${prefix}${xx}" $value
        }
    }
    return $propdict
}

proc v04a_set_dict {fh rfdc label propdict} {
    set n [expr {[llength $propdict] / 2}]
    if {[catch {set_property -dict $propdict $rfdc} err]} {
        v04a_log $fh "SET-DICT ERROR $label ($n properties): $err"
        set info [v04a_errinfo]
        if {$info ne "" && $info ne $err} { v04a_log $fh "  errorInfo: $info" }
        return 0
    }
    v04a_log $fh "SET-DICT OK $label ($n properties)"
    return 1
}

proc v04a_decimation_is_2 {fh rfdc pair_ids label} {
    set parts {}
    set all2 1
    foreach xx $pair_ids {
        set got [v04a_get "CONFIG.ADC_Decimation_Mode${xx}" $rfdc]
        lappend parts "${xx}={$got}"
        if {![v04a_num_eq $got 2]} { set all2 0 }
    }
    v04a_log $fh "Decimation readback ($label): [join $parts { }]"
    return $all2
}

proc v04a_bool_true {value} {
    return [expr {$value eq "true" || $value eq "TRUE" || $value eq "1"}]
}

proc v04a_mts_true {rfdc} {
    return [expr {[v04a_bool_true [v04a_get CONFIG.ADC0_Multi_Tile_Sync $rfdc]] && \
                  [v04a_bool_true [v04a_get CONFIG.ADC1_Multi_Tile_Sync $rfdc]] && \
                  [v04a_bool_true [v04a_get CONFIG.DAC0_Multi_Tile_Sync $rfdc]] && \
                  [v04a_bool_true [v04a_get CONFIG.DAC1_Multi_Tile_Sync $rfdc]]}]
}

proc v04a_checkpoint {fh rfdc label} {
    set parts [list "CHECKPOINT $label:"]
    foreach kind {ADC DAC} {
        foreach tile {0 1} {
            lappend parts "${kind}${tile}_MTS={[v04a_get CONFIG.${kind}${tile}_Multi_Tile_Sync $rfdc]}"
            lappend parts "${kind}${tile}_FABRIC={[v04a_get CONFIG.${kind}${tile}_Fabric_Freq $rfdc]}"
        }
    }
    v04a_log $fh [join $parts " "]
}

proc v04a_capture_tile_invariants {rfdc} {
    # Everything needed to prove the ADC rate change did not silently
    # reprogramme tile clocking/MTS.  ADC Fabric_Freq is intentionally
    # excluded (500 -> 250 is the change under test); DAC Fabric_Freq
    # must not move.
    set captured [dict create]
    foreach kind {ADC DAC} {
        foreach tile {0 1} {
            set suffixes {Enable Sampling_Rate Refclk_Freq Outclk_Freq \
                PLL_Enable Clock_Source Clock_Dist Multi_Tile_Sync}
            if {$kind eq "DAC"} { lappend suffixes Fabric_Freq }
            if {$kind eq "ADC"} { lappend suffixes Band }
            foreach suffix $suffixes {
                set prop "CONFIG.${kind}${tile}_${suffix}"
                dict set captured $prop [v04a_get $prop $rfdc]
            }
        }
    }
    return $captured
}

proc v04a_restore_mts {fh rfdc label} {
    # The RFDC GUI/dependency logic is known to clear MTS while other
    # settings are being changed; re-checking it after the final datapath
    # values are in place is therefore tested explicitly, never assumed.
    # ADC MTS is the DOA requirement; DAC tiles 0/1 are restored too
    # because the MTS base had them enabled for coherent HIL loopback.
    set propdict [dict create \
        CONFIG.ADC0_Multi_Tile_Sync true \
        CONFIG.ADC1_Multi_Tile_Sync true \
        CONFIG.DAC0_Multi_Tile_Sync true \
        CONFIG.DAC1_Multi_Tile_Sync true]
    set ok [v04a_set_dict $fh $rfdc "MTS restore ($label)" $propdict]
    if {!$ok || ![v04a_mts_true $rfdc]} {
        set dummy_failures {}
        foreach kind {ADC DAC} {
            foreach tile {0 1} {
                v04a_set $fh $rfdc "CONFIG.${kind}${tile}_Multi_Tile_Sync" true 0 dummy_failures
            }
        }
    }
    set now [v04a_mts_true $rfdc]
    v04a_log $fh "MTS RESTORE RESULT ($label)=[expr {$now ? {PASS} : {FAIL}}] ADC0={[v04a_get CONFIG.ADC0_Multi_Tile_Sync $rfdc]} ADC1={[v04a_get CONFIG.ADC1_Multi_Tile_Sync $rfdc]} DAC0={[v04a_get CONFIG.DAC0_Multi_Tile_Sync $rfdc]} DAC1={[v04a_get CONFIG.DAC1_Multi_Tile_Sync $rfdc]}"
    v04a_checkpoint $fh $rfdc "after MTS restore ($label)"
    return $now
}

proc v04a_report_state {fh rfdc label} {
    v04a_log $fh "## STATE: $label"
    foreach tile {0 1} {
        foreach suffix {Enable Sampling_Rate Refclk_Freq Fabric_Freq Outclk_Freq \
                        PLL_Enable Clock_Source Clock_Dist Multi_Tile_Sync Band} {
            set prop "CONFIG.ADC${tile}_${suffix}"
            v04a_log $fh "$prop = {[v04a_get $prop $rfdc]}"
        }
    }
    foreach tile {0 1} {
        foreach suffix {Enable Sampling_Rate Refclk_Freq Fabric_Freq Outclk_Freq \
                        PLL_Enable Clock_Source Clock_Dist Multi_Tile_Sync} {
            set prop "CONFIG.DAC${tile}_${suffix}"
            v04a_log $fh "$prop = {[v04a_get $prop $rfdc]}"
        }
    }
    set slice_props {Slice%s_Enable Data_Type%s Data_Width%s Decimation_Mode%s \
        Mixer_Mode%s Mixer_Type%s Coarse_Mixer_Freq%s NCO_Freq%s NCO_Phase%s \
        Neg_Quadrature%s Nyquist%s CalOpt_Mode%s Dither%s}
    foreach slice {00 01 02 03 10 11 12 13} {
        set parts [list "slice $slice:"]
        foreach pattern $slice_props {
            set short [format $pattern $slice]
            lappend parts "$short={[v04a_get CONFIG.ADC_$short $rfdc]}"
        }
        v04a_log $fh [join $parts " "]
    }
    v04a_log $fh "-- RFDC m*_axis interface pins ($label)"
    foreach pin [lsort [get_bd_intf_pins -quiet -of_objects $rfdc]] {
        set pname [get_property NAME $pin]
        if {![string match "m*_axis" $pname]} { continue }
        set net [lindex [get_bd_intf_nets -quiet -of_objects $pin] 0]
        set peers {}
        if {$net ne ""} {
            foreach peer [get_bd_intf_pins -quiet -of_objects $net] {
                if {$peer ne $pin} { lappend peers $peer }
            }
        }
        set width "?"
        foreach ppin [get_bd_pins -quiet "$rfdc/${pname}_tdata"] {
            set lft [v04a_get LEFT $ppin]
            set rgt [v04a_get RIGHT $ppin]
            if {![catch {expr {$lft - $rgt + 1}} w]} { set width $w }
        }
        v04a_log $fh "$pname bytes={[v04a_get CONFIG.TDATA_NUM_BYTES $pin]} width=$width FREQ_HZ={[v04a_get CONFIG.FREQ_HZ $pin]} CLK_DOMAIN={[v04a_get CONFIG.CLK_DOMAIN $pin]} peers={$peers}"
    }
    foreach clkpin {m0_axis_aclk m1_axis_aclk} {
        set pin [lindex [get_bd_pins -quiet "$rfdc/$clkpin"] 0]
        set srcs {}
        if {$pin ne ""} {
            set net [lindex [get_bd_nets -quiet -of_objects $pin] 0]
            if {$net ne ""} {
                foreach ppin [get_bd_pins -quiet -of_objects $net] {
                    if {$ppin ne $pin} { lappend srcs $ppin }
                }
            }
        }
        v04a_log $fh "$clkpin driven by {$srcs} (V07 must move this to the 250 MHz clk_out2 domain)"
    }
    v04a_log $fh ""
}

set failures {}
set warnings {}

v04a_log $fh "# V04 scratch RFDC apply v1.2 atomic-dict + MTS invariant (scratch project only) - Vivado [lindex [version] 1]"
v04a_log $fh "# input_xpr=$input_xpr"
v04a_log $fh "# scratch_xpr=$scratch_xpr"
v04a_log $fh ""

# --- Copy input project to the scratch project ------------------------------
v04a_log $fh "V04 SCRATCH: opening input project ..."
open_project $input_xpr
set in_part [get_property PART [current_project]]
if {$in_part ne $::PART_PINNED} {
    close_project
    close $fh
    error "V04 scratch: input project part $in_part != pinned $::PART_PINNED"
}
file mkdir $scratch_dir
v04a_log $fh "V04 SCRATCH: save_project_as -> $scratch_dir (copy can take a while) ..."
save_project_as -force $scratch_name $scratch_dir
close_project
if {![file exists $scratch_xpr]} {
    close $fh
    error "V04 scratch: scratch project was not created at $scratch_xpr"
}

# --- Open scratch BD, record before-state -----------------------------------
v04a_log $fh "V04 SCRATCH: opening scratch project + mts.bd ..."
open_project $scratch_xpr
set bd_file [lindex [get_files -quiet */mts.bd] 0]
if {$bd_file eq ""} {
    close_project
    close $fh
    error "V04 scratch: mts.bd not found in scratch project"
}
open_bd_design $bd_file
set rfdc [lindex [get_bd_cells -hierarchical -quiet \
    -filter {VLNV =~ *usp_rf_data_converter*}] 0]
if {$rfdc eq ""} {
    close_project
    close $fh
    error "V04 scratch: no usp_rf_data_converter cell in scratch BD"
}
set rfdc_vlnv [get_property VLNV $rfdc]
if {$rfdc_vlnv ne $::IPVLNV(rfdc)} {
    close_project
    close $fh
    error "V04 scratch: RFDC VLNV $rfdc_vlnv != pinned $::IPVLNV(rfdc)"
}
v04a_log $fh "RFDC cell=$rfdc vlnv=$rfdc_vlnv"
v04a_report_state $fh $rfdc "BEFORE (scratch copy of MTS work BD)"
set ::v04a_before_tiles [v04a_capture_tile_invariants $rfdc]
v04a_log $fh "TILE INVARIANTS CAPTURED ([expr {[dict size $::v04a_before_tiles]}] properties; asserted again after reopen)"
v04a_checkpoint $fh $rfdc "BEFORE"

# --- Apply candidate CONFIG (pair heads; staged atomic dicts) ---------------
v04a_log $fh "## APPLY (staged atomic dicts; see header for why)"
set pair_ids {00 02 10 12}

# Stage 1: establish a self-consistent mixer mode (I/Q + Real->I/Q + Fine)
# in one transaction.  Fallback order is the exact one-by-one sequence the
# first run proved Vivado accepts for these three groups.
set mode_groups {{Data_Type 1} {Mixer_Mode 0} {Mixer_Type 2}}
if {![v04a_set_dict $fh $rfdc "mode: I/Q + Real->I/Q + Fine" \
        [v04a_build_dict $mode_groups $pair_ids]]} {
    lappend warnings "mode dict failed; used one-by-one fallback (see SET lines)"
    foreach group $mode_groups {
        lassign $group prefix value
        foreach xx $pair_ids {
            v04a_set $fh $rfdc "CONFIG.ADC_${prefix}${xx}" $value 0 failures
        }
    }
}

v04a_checkpoint $fh $rfdc "after stage 1 mode dict"

# Stage 2: rate change.  Width+decimation for ALL pairs in one dict: both
# pairs of a tile share that tile's fabric clock, so no intermediate state
# may mix 1x/500 MHz with 2x/250 MHz inside a tile.
set rate_groups {{Data_Width 8} {Decimation_Mode 2}}
if {![v04a_set_dict $fh $rfdc "rate: width8 + decimation2 (all pairs)" \
        [v04a_build_dict $rate_groups $pair_ids]]} {
    lappend warnings "all-pairs rate dict failed; per-tile retry follows"
}
if {![v04a_decimation_is_2 $fh $rfdc $pair_ids "after all-pairs rate dict"]} {
    foreach tile_pairs {{00 02} {10 12}} {
        v04a_set_dict $fh $rfdc "rate retry tile pairs $tile_pairs" \
            [v04a_build_dict $rate_groups $tile_pairs]
    }
    v04a_decimation_is_2 $fh $rfdc $pair_ids "after per-tile rate retries"
}

v04a_checkpoint $fh $rfdc "after stage 2 rate dict/retries"

# Stage 3: tuning/analog settings (NCO needs Fine from stage 1).
set tune_groups {{NCO_Freq -3.0} {NCO_Phase 0} {Nyquist 1} {CalOpt_Mode 1}}
if {![v04a_set_dict $fh $rfdc "tune: NCO -3.0/phase0 + Zone2 + CalOpt Mode2" \
        [v04a_build_dict $tune_groups $pair_ids]]} {
    lappend warnings "tune dict failed; used one-by-one fallback (see SET lines)"
    foreach group $tune_groups {
        lassign $group prefix value
        foreach xx $pair_ids {
            v04a_set $fh $rfdc "CONFIG.ADC_${prefix}${xx}" $value 0 failures
        }
    }
}

# Final decimation retry now that every dependent setting is at its final
# value (covers IP dependency orders we have not anticipated).
if {![v04a_decimation_is_2 $fh $rfdc $pair_ids "after tune stage"]} {
    v04a_log $fh "Decimation still not 2x; final all-pairs rate retry ..."
    v04a_set_dict $fh $rfdc "rate final retry (all pairs)" \
        [v04a_build_dict $rate_groups $pair_ids]
    v04a_decimation_is_2 $fh $rfdc $pair_ids "after final rate retry"
}

v04a_checkpoint $fh $rfdc "after stage 3 tune/final rate retry"
foreach tile {0 1} {
    # Fabric_Freq: PG269 defines it as the required AXI4-Stream clock
    # determined by Fs/decimation/width, so validate may compute it.  The
    # direct write is a request only (first run: silently kept 500 while
    # decimation was still 1x); the asserted gate is the post-validate,
    # persisted readback == 250.  v1.2 skips this write when the rate dict
    # already computed 250, removing one unnecessary transaction that
    # could perturb unrelated dependency state such as MTS.
    set current_fabric [v04a_get "CONFIG.ADC${tile}_Fabric_Freq" $rfdc]
    if {[v04a_num_eq $current_fabric 250.000]} {
        v04a_log $fh "ADC${tile}_Fabric_Freq already {$current_fabric}; direct write skipped"
    } elseif {![v04a_set $fh $rfdc "CONFIG.ADC${tile}_Fabric_Freq" 250.000 0 failures]} {
        lappend warnings "ADC${tile}_Fabric_Freq not directly settable; relying on validate to compute 250"
    }
}
v04a_checkpoint $fh $rfdc "after Fabric_Freq stage"
v04a_report_state $fh $rfdc "AFTER SET (pre-validate)"

# If a datapath stage already cleared MTS, restore it before validate so
# validate sees (and keeps) the MTS SYSREF ports/nets from the base BD.
if {![v04a_mts_true $rfdc]} {
    lappend warnings "MTS was cleared during the datapath apply; restore attempted before validate (see CHECKPOINT lines for the stage)"
    if {![v04a_restore_mts $fh $rfdc "pre-validate"]} {
        lappend failures "Multi_Tile_Sync could not be restored before validate"
    }
}

# --- Validate (reported separately; V07 rewiring still pending) -------------
v04a_log $fh "V04 SCRATCH: validate_bd_design (legacy 500 MHz capture still attached; failures here are classified, not hidden) ..."
set validate_rc [catch {validate_bd_design} validate_msg]
if {$validate_rc} {
    v04a_log $fh "FULL BD VALIDATE RESULT=FAIL: $validate_msg"
} else {
    v04a_log $fh "FULL BD VALIDATE RESULT=PASS"
}
if {$validate_rc} {
    set info [v04a_errinfo]
    if {$info ne "" && $info ne $validate_msg} {
        v04a_log $fh "validate errorInfo: $info"
    }
}
v04a_log $fh "(Detailed Vivado ERROR/WARNING text is in the console/log; SET-DICT failures above include ::errorInfo in this report.)"
v04a_report_state $fh $rfdc "AFTER VALIDATE"
v04a_checkpoint $fh $rfdc "after validate #1"

# Final MTS gate before saving.  If validate itself clears MTS, restore
# it and validate once more; if the second validate clears it again,
# restore after validate and let the persisted assertions decide.  The
# REVIEW warning distinguishes that fragile case from a clean pass.
if {![v04a_mts_true $rfdc]} {
    lappend warnings "MTS is off after validate #1; restore + validate #2 attempted"
    if {[v04a_restore_mts $fh $rfdc "after validate #1"]} {
        v04a_log $fh "V04 SCRATCH: validate_bd_design #2 after MTS restore ..."
        set validate2_rc [catch {validate_bd_design} validate2_msg]
        if {$validate2_rc} {
            v04a_log $fh "FULL BD VALIDATE #2 RESULT=FAIL: $validate2_msg"
            set info2 [v04a_errinfo]
            if {$info2 ne "" && $info2 ne $validate2_msg} {
                v04a_log $fh "validate #2 errorInfo: $info2"
            }
        } else {
            v04a_log $fh "FULL BD VALIDATE #2 RESULT=PASS"
        }
        set validate_rc $validate2_rc
        v04a_report_state $fh $rfdc "AFTER MTS RESTORE + VALIDATE #2"
        v04a_checkpoint $fh $rfdc "after MTS restore + validate #2"
        if {![v04a_mts_true $rfdc]} {
            lappend warnings "validate #2 cleared MTS again; final restore is after validate, so V07 must re-check MTS after every validate until the clock/SYSREF condition is identified"
            if {![v04a_restore_mts $fh $rfdc "final, after validate #2"]} {
                lappend failures "Multi_Tile_Sync could not be restored after validate #2"
            }
        }
    } else {
        lappend failures "Multi_Tile_Sync could not be restored after validate #1"
    }
}

# --- Persist scratch BD and prove readback on reopen ------------------------
if {[catch {save_bd_design} save_msg]} {
    lappend failures "save_bd_design (scratch) failed: $save_msg"
    v04a_log $fh "SAVE (scratch BD) ERROR: $save_msg"
} else {
    v04a_log $fh "SAVE (scratch BD) OK"
}
close_project

v04a_log $fh "V04 SCRATCH: reopening scratch project for persisted readback ..."
open_project $scratch_xpr
set bd_file [lindex [get_files -quiet */mts.bd] 0]
open_bd_design $bd_file
set rfdc [lindex [get_bd_cells -hierarchical -quiet \
    -filter {VLNV =~ *usp_rf_data_converter*}] 0]
v04a_report_state $fh $rfdc "PERSISTED (after reopen)"

# --- Assertions on the persisted state --------------------------------------
v04a_log $fh "## ASSERTIONS (persisted state)"
array set target {
    Data_Type 1 Data_Width 8 Decimation_Mode 2 Mixer_Mode 0 Mixer_Type 2
    NCO_Freq -3.0 NCO_Phase 0 Nyquist 1 CalOpt_Mode 1
}
foreach xx $pair_ids {
    foreach prefix {Data_Type Data_Width Decimation_Mode Mixer_Mode Mixer_Type \
                    NCO_Freq NCO_Phase Nyquist CalOpt_Mode} {
        set got [v04a_get "CONFIG.ADC_${prefix}${xx}" $rfdc]
        if {![v04a_num_eq $got $target($prefix)]} {
            lappend failures "pair $xx $prefix: got {$got}, expected {$target($prefix)}"
            v04a_log $fh "ASSERT FAIL ADC_${prefix}${xx} = {$got} (expected {$target($prefix)})"
        }
    }
}
foreach tile {0 1} {
    set got [v04a_get "CONFIG.ADC${tile}_Fabric_Freq" $rfdc]
    if {![v04a_num_eq $got 250.000]} {
        lappend failures "ADC${tile}_Fabric_Freq: got {$got}, expected 250.000"
        v04a_log $fh "ASSERT FAIL ADC${tile}_Fabric_Freq = {$got} (expected 250.000)"
    }
    set got_out [v04a_get "CONFIG.ADC${tile}_Outclk_Freq" $rfdc]
    if {![v04a_num_eq $got_out 250.000]} {
        lappend warnings "ADC${tile}_Outclk_Freq is {$got_out}, expected unchanged 250.000"
    }
}
foreach tile {0 1} {
    foreach kind {ADC DAC} {
        set got_mts [v04a_get "CONFIG.${kind}${tile}_Multi_Tile_Sync" $rfdc]
        if {![v04a_bool_true $got_mts]} {
            lappend failures "${kind}${tile}_Multi_Tile_Sync: got {$got_mts}, expected true (MTS is mandatory; v1.1 missed this assertion)"
            v04a_log $fh "ASSERT FAIL CONFIG.${kind}${tile}_Multi_Tile_Sync = {$got_mts} (expected true)"
        }
    }
}
if {[info exists ::v04a_before_tiles]} {
    dict for {prop expected} $::v04a_before_tiles {
        if {$expected eq "<unavailable>"} { continue }
        set got_inv [v04a_get $prop $rfdc]
        if {![string equal -nocase $got_inv $expected] && ![v04a_num_eq $got_inv $expected]} {
            lappend failures "tile invariant $prop changed: before {$expected}, persisted {$got_inv}"
            v04a_log $fh "ASSERT FAIL invariant $prop = {$got_inv} (before {$expected})"
        }
    }
} else {
    lappend warnings "before-state tile invariants were not captured; only explicit MTS/fabric assertions ran"
}
v04a_checkpoint $fh $rfdc "PERSISTED ASSERTIONS"
set stream_names {}
foreach pin [get_bd_intf_pins -quiet -of_objects $rfdc] {
    lappend stream_names [get_property NAME $pin]
}
foreach want {m00_axis m01_axis m02_axis m03_axis m10_axis m11_axis m12_axis m13_axis} {
    if {[lsearch -exact $stream_names $want] < 0} {
        lappend failures "expected stream $want not present after apply"
        v04a_log $fh "ASSERT FAIL stream $want missing"
    }
}
# Odd slices are the Q legs of each pair; upstream writes pair heads only.
# Report (do not fail) any odd-slice value Vivado did not propagate, so the
# evidence is reviewed explicitly instead of assumed.
foreach odd {01 03 11 13} {
    foreach prefix {Data_Type Decimation_Mode Mixer_Mode Mixer_Type Nyquist CalOpt_Mode} {
        set got [v04a_get "CONFIG.ADC_${prefix}${odd}" $rfdc]
        if {![v04a_num_eq $got $target($prefix)]} {
            lappend warnings "odd slice $odd $prefix = {$got} (pair target {$target($prefix)}); review whether this Q-leg parameter is inert or must be written in V07"
        }
    }
}

foreach w $warnings { v04a_log $fh "REVIEW: $w" }
if {[llength $failures] > 0} {
    foreach f $failures { v04a_log $fh "FAILURE: $f" }
    v04a_log $fh "V04 SCRATCH CONFIG RESULT=FAIL ([llength $failures] failures; see report $out_file)"
    close $fh
    close_project
    error "V04 scratch apply FAILED with [llength $failures] assertion failures (report: $out_file). Input project was not modified."
}
if {$validate_rc} {
    v04a_log $fh "V04 SCRATCH CONFIG RESULT=PASS (full-BD validate still FAILS as expected until V07 moves ADC streams to 250 MHz and replaces the MTS capture path)"
} else {
    v04a_log $fh "V04 SCRATCH CONFIG RESULT=PASS (full-BD validate also passed in scratch)"
}
v04a_log $fh "Input project untouched: $input_xpr"
v04a_log $fh "Scratch project (deletable): $scratch_xpr"
close $fh
close_project
puts "V04 SCRATCH APPLY PASS (report: $out_file)"
