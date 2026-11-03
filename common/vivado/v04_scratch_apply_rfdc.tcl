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
# v1.3 (after the v1.2 user-PC run, 2026-11-03): v1.2 localized the MTS
# flip to stage 2 (Data_Width/Decimation dict; ADC fabric 500 -> 250 MHz
# while DAC0/1 stayed MTS-true at 500 MHz), and both late restores failed.
# v1.3 therefore reports every RFDC sync/PL-clock property, normalizes
# CONFIG.PL_Clock_Freq to the 500 MHz common PL clock before stage 2 if
# that property exists, and -- only if MTS still flips -- runs ordered,
# fully logged diagnostics: PL clock 500/250, ADC-first sequencing with
# DAC MTS temporarily off, ADC AXIS clock pins moved to the existing
# 250 MHz clkRFdiv2 net, an equal-fabric DAC-interpolation-2 branch, and
# finally an ADC Data_Width=4/fabric-500 probe (reverted).  A DAC-250
# success is reported as PASS-DIAGNOSTIC, never as production PASS: it
# changes the DAC loopback contract and needs an explicit V04 decision.
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
    lappend parts "PL_Clock_Freq={[v04a_get CONFIG.PL_Clock_Freq $rfdc]}"
    v04a_log $fh [join $parts " "]
}

proc v04a_checkpoint_all_tiles {fh rfdc label} {
    set parts [list "ALL-TILE CHECKPOINT $label:"]
    foreach kind {ADC DAC} {
        foreach tile {0 1 2 3} {
            lappend parts "${kind}${tile}_EN={[v04a_get CONFIG.${kind}${tile}_Enable $rfdc]}"
            lappend parts "${kind}${tile}_MTS={[v04a_get CONFIG.${kind}${tile}_Multi_Tile_Sync $rfdc]}"
            lappend parts "${kind}${tile}_FABRIC={[v04a_get CONFIG.${kind}${tile}_Fabric_Freq $rfdc]}"
        }
    }
    lappend parts "PL_Clock_Freq={[v04a_get CONFIG.PL_Clock_Freq $rfdc]}"
    v04a_log $fh [join $parts " "]
}

proc v04a_report_sync_props {fh rfdc label} {
    # Generated BD Tcl omits properties still at their component default
    # (PL_Clock_Freq is the known example), so enumerate the live cell
    # instead of trusting upstream Tcl exports.
    set selected {}
    foreach prop [lsort [list_property $rfdc]] {
        set take 0
        if {[regexp -nocase {(PL_Clock|PLClock|Sysref|Multi_Tile|Master_Tile)} $prop]} {
            set take 1
        } elseif {[string match "CONFIG.*" $prop] && \
                  ![string match "CONFIG.ADC*" $prop] && \
                  ![string match "CONFIG.DAC*" $prop] && \
                  [regexp -nocase {(Clock|Sync|Freq)} $prop]} {
            set take 1
        }
        if {$take} { lappend selected $prop }
    }
    v04a_log $fh "SYNC/PL-CLOCK PROPERTIES ($label): [llength $selected] live properties"
    foreach prop $selected {
        v04a_log $fh "  $prop = {[v04a_get $prop $rfdc]}"
    }
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

proc v04a_mts_kind_true {rfdc kind} {
    return [expr {[v04a_bool_true [v04a_get "CONFIG.${kind}0_Multi_Tile_Sync" $rfdc]] && \
                  [v04a_bool_true [v04a_get "CONFIG.${kind}1_Multi_Tile_Sync" $rfdc]]}]
}

proc v04a_set_mts_kind {fh rfdc kind value label} {
    set propdict [dict create \
        "CONFIG.${kind}0_Multi_Tile_Sync" $value \
        "CONFIG.${kind}1_Multi_Tile_Sync" $value]
    v04a_set_dict $fh $rfdc "$kind MTS <- $value ($label)" $propdict
    set want_true [v04a_bool_true $value]
    if {[v04a_mts_kind_true $rfdc $kind] != $want_true} {
        set dummy_failures {}
        foreach tile {0 1} {
            v04a_set $fh $rfdc "CONFIG.${kind}${tile}_Multi_Tile_Sync" $value 0 dummy_failures
        }
    }
    set now [v04a_mts_kind_true $rfdc $kind]
    v04a_log $fh "$kind MTS SET RESULT ($label)=[expr {$now == $want_true ? {PASS} : {FAIL}}] ${kind}0={[v04a_get CONFIG.${kind}0_Multi_Tile_Sync $rfdc]} ${kind}1={[v04a_get CONFIG.${kind}1_Multi_Tile_Sync $rfdc]}"
    v04a_checkpoint $fh $rfdc "after $kind MTS <- $value ($label)"
    return [expr {$now == $want_true}]
}

proc v04a_restore_mts_sequence {fh rfdc label} {
    # Stronger ordering probe than the all-at-once restore: first make ADC
    # the only MTS group in ONE dict (ADC on + DAC off, so the final state
    # still has an MTS group and the user_sysref pins should not vanish),
    # then bring DAC MTS back.  Each step is checkpointed so a cross-group
    # side effect cannot hide; persisted user_sysref connectivity is also
    # asserted at the end of the script.
    v04a_log $fh "MTS SEQUENCE PROBE ($label): atomic ADC-on/DAC-off -> DAC on"
    set propdict [dict create \
        CONFIG.ADC0_Multi_Tile_Sync true \
        CONFIG.ADC1_Multi_Tile_Sync true \
        CONFIG.DAC0_Multi_Tile_Sync false \
        CONFIG.DAC1_Multi_Tile_Sync false]
    v04a_set_dict $fh $rfdc "MTS sequence atomic ADC-on/DAC-off ($label)" $propdict
    set adc_ok [v04a_mts_kind_true $rfdc ADC]
    if {!$adc_ok} {
        set adc_ok [v04a_set_mts_kind $fh $rfdc ADC true "$label sequence ADC retry"]
    }
    if {!$adc_ok} {
        v04a_set_mts_kind $fh $rfdc DAC true "$label sequence DAC restore after ADC fail"
        v04a_ensure_user_sysref_connected $fh $rfdc "$label sequence after ADC fail"
        v04a_log $fh "MTS SEQUENCE RESULT ($label)=FAIL (ADC could not be enabled as sole MTS group)"
        return 0
    }
    if {[v04a_mts_kind_true $rfdc DAC]} {
        v04a_set_mts_kind $fh $rfdc DAC false "$label sequence ensure DAC off"
    }
    set dac_ok [v04a_set_mts_kind $fh $rfdc DAC true "$label sequence DAC on"]
    v04a_ensure_user_sysref_connected $fh $rfdc "$label sequence complete"
    set now [v04a_mts_true $rfdc]
    v04a_log $fh "MTS SEQUENCE RESULT ($label)=[expr {$now ? {PASS} : {FAIL}}] (ADC sole-group step=$adc_ok DAC-on step=$dac_ok)"
    return $now
}

proc v04a_restore_mts_with_sequence {fh rfdc label} {
    if {[v04a_restore_mts $fh $rfdc $label]} { return 1 }
    return [v04a_restore_mts_sequence $fh $rfdc $label]
}

proc v04a_pl_clock_exists {rfdc} {
    return [expr {[lsearch -exact [list_property $rfdc] CONFIG.PL_Clock_Freq] >= 0}]
}

proc v04a_set_pl_clock {fh rfdc value label} {
    if {![v04a_pl_clock_exists $rfdc]} {
        v04a_log $fh "PL CLOCK SET ($label): CONFIG.PL_Clock_Freq is ABSENT on this RFDC cell; branch skipped"
        return 0
    }
    set dummy_failures {}
    set ok [v04a_set $fh $rfdc CONFIG.PL_Clock_Freq $value 0 dummy_failures]
    set got [v04a_get CONFIG.PL_Clock_Freq $rfdc]
    set now [expr {$ok && [v04a_num_eq $got $value]}]
    v04a_log $fh "PL CLOCK RESULT ($label)=[expr {$now ? {PASS} : {FAIL}}] PL_Clock_Freq={$got} expected {$value}"
    v04a_checkpoint $fh $rfdc "after PL clock set ($label)"
    return $now
}

proc v04a_try_pl_all {fh rfdc freq label} {
    # Test both groups from a real false->true transition at this PL clock
    # value; a pre-existing true that was never re-evaluated is not proof.
    if {![v04a_set_pl_clock $fh $rfdc $freq $label]} { return 0 }
    set adc_ok [v04a_set_mts_kind $fh $rfdc ADC true "$label ADC"]
    if {!$adc_ok} {
        v04a_log $fh "PL-CLOCK BRANCH RESULT ($label)=FAIL at ADC restore (PL_Clock_Freq=$freq)"
        return 0
    }
    v04a_set_mts_kind $fh $rfdc DAC false "$label DAC retoggle off"
    set dac_ok [v04a_set_mts_kind $fh $rfdc DAC true "$label DAC retoggle on"]
    set now [v04a_mts_true $rfdc]
    v04a_log $fh "PL-CLOCK BRANCH RESULT ($label)=[expr {$now ? {PASS} : {FAIL}}] (PL_Clock_Freq=$freq ADC=$adc_ok DAC-retoggle=$dac_ok)"
    return $now
}

proc v04a_normalize_dac_mts_500 {fh rfdc label} {
    # Return to the known-good DAC baseline between diagnostic branches.
    if {[v04a_pl_clock_exists $rfdc]} {
        v04a_set_pl_clock $fh $rfdc 500.000 "$label normalize"
    }
    set ok [v04a_set_mts_kind $fh $rfdc DAC true "$label normalize"]
    v04a_checkpoint $fh $rfdc "after DAC baseline normalize ($label)"
    return $ok
}

proc v04a_pin_drivers {pin} {
    set drivers {}
    if {$pin eq ""} { return $drivers }
    set net [lindex [get_bd_nets -quiet -of_objects $pin] 0]
    if {$net ne ""} {
        foreach peer [get_bd_pins -quiet -of_objects $net] {
            if {$peer ne $pin} { lappend drivers $peer }
        }
    }
    return $drivers
}

proc v04a_capture_user_sysref_source {rfdc} {
    foreach syspin {user_sysref_adc user_sysref_dac} {
        set pin [lindex [get_bd_pins -quiet "$rfdc/$syspin"] 0]
        foreach driver [v04a_pin_drivers $pin] {
            if {![string match "$rfdc/*" $driver]} { return $driver }
        }
    }
    return ""
}

proc v04a_ensure_user_sysref_connected {fh rfdc label} {
    # Toggling MTS can regenerate the RFDC user_sysref pins.  If a pin
    # reappears unconnected, reconnect it to the exact source captured
    # from the MTS base so later branches/validate see the same BD graph.
    if {![info exists ::v04a_user_sysref_source] || $::v04a_user_sysref_source eq ""} {
        v04a_log $fh "USER_SYSREF ENSURE ($label): no source captured; skipped"
        return 0
    }
    set source [lindex [get_bd_pins -quiet $::v04a_user_sysref_source] 0]
    if {$source eq ""} {
        v04a_log $fh "USER_SYSREF ENSURE ($label): captured source {$::v04a_user_sysref_source} not found"
        return 0
    }
    set all_ok 1
    foreach syspin {user_sysref_adc user_sysref_dac} {
        set pin [lindex [get_bd_pins -quiet "$rfdc/$syspin"] 0]
        if {$pin eq ""} {
            v04a_log $fh "USER_SYSREF ENSURE ($label): $syspin pin ABSENT"
            set all_ok 0
            continue
        }
        set drivers [v04a_pin_drivers $pin]
        if {[lsearch -exact $drivers $source] >= 0} {
            v04a_log $fh "USER_SYSREF ENSURE ($label): $syspin already driven by $source"
            continue
        }
        if {[llength $drivers] > 0} {
            v04a_log $fh "USER_SYSREF ENSURE ($label): $syspin driven by {$drivers}; left unchanged"
            continue
        }
        if {[catch {connect_bd_net $source $pin} err]} {
            v04a_log $fh "USER_SYSREF ENSURE ($label): reconnect $syspin ERROR: $err"
            set info [v04a_errinfo]
            if {$info ne "" && $info ne $err} { v04a_log $fh "  errorInfo: $info" }
            set all_ok 0
        } else {
            v04a_log $fh "USER_SYSREF ENSURE ($label): reconnected $syspin to $source; drivers now {[v04a_pin_drivers $pin]}"
        }
    }
    return $all_ok
}

proc v04a_move_adc_aclk {fh rfdc target_name target_label} {
    # Scratch-only clock move between the two existing MTSclkwiz outputs:
    # clkRF (500 MHz) and clkRFdiv2 (250 MHz).  The 250 MHz move is the
    # direction V07 must make anyway; restoring 500 MHz after a failed D4
    # branch keeps D5/D6 isolated.  Downstream capture hierarchies stay on
    # 500 MHz in scratch, so validate remains classified, not the gate.
    set target [lindex [get_bd_pins -quiet "/clocktreeMTS/$target_name"] 0]
    if {$target eq ""} {
        foreach candidate [get_bd_pins -quiet -hierarchical "*$target_name"] {
            if {[get_property NAME $candidate] eq $target_name} {
                set target $candidate
                break
            }
        }
    }
    if {$target eq ""} {
        v04a_log $fh "ADC ACLK REWIRE ERROR: $target_name ($target_label) pin not found"
        return 0
    }
    v04a_log $fh "ADC ACLK REWIRE: target $target_label source pin = $target"
    foreach clkpin {m0_axis_aclk m1_axis_aclk} {
        set pin [lindex [get_bd_pins -quiet "$rfdc/$clkpin"] 0]
        if {$pin eq ""} {
            v04a_log $fh "ADC ACLK REWIRE ERROR: $rfdc/$clkpin not found"
            return 0
        }
        set drivers [v04a_pin_drivers $pin]
        v04a_log $fh "ADC ACLK REWIRE: $clkpin currently driven by {$drivers}"
        if {[lsearch -exact $drivers $target] >= 0} {
            v04a_log $fh "ADC ACLK REWIRE: $clkpin already on $target_name"
            continue
        }
        set net [lindex [get_bd_nets -quiet -of_objects $pin] 0]
        if {$net ne ""} {
            if {[catch {disconnect_bd_net $net $pin} err]} {
                v04a_log $fh "ADC ACLK REWIRE ERROR disconnect $clkpin: $err"
                set info [v04a_errinfo]
                if {$info ne "" && $info ne $err} { v04a_log $fh "  errorInfo: $info" }
                return 0
            }
        }
        if {[catch {connect_bd_net $target $pin} err]} {
            v04a_log $fh "ADC ACLK REWIRE ERROR connect $clkpin: $err"
            set info [v04a_errinfo]
            if {$info ne "" && $info ne $err} { v04a_log $fh "  errorInfo: $info" }
            return 0
        }
        v04a_log $fh "ADC ACLK REWIRE: $clkpin now driven by {[v04a_pin_drivers $pin]}"
    }
    return 1
}

proc v04a_rewire_adc_aclk_250 {fh rfdc} {
    return [v04a_move_adc_aclk $fh $rfdc clkRFdiv2 "250 MHz"]
}

proc v04a_restore_adc_aclk_500 {fh rfdc} {
    return [v04a_move_adc_aclk $fh $rfdc clkRF "500 MHz"]
}

proc v04a_set_dac_interpolation {fh rfdc value label} {
    # Active DAC slices in the MTS base are 00/02, 10/12 and 20 (tile 2 is
    # enabled without MTS).  Move every active tile together, then per
    # tile on retry, for the same shared-fabric-clock reason as the ADCs.
    set active_ids {00 02 10 12 20}
    set build_ids {{00 02 10 12 20} {00 02} {10 12} {20}}
    foreach ids $build_ids {
        set propdict {}
        foreach xx $ids {
            lappend propdict "CONFIG.DAC_Data_Width${xx}" 8
            lappend propdict "CONFIG.DAC_Interpolation_Mode${xx}" $value
        }
        v04a_set_dict $fh $rfdc "DAC width8 + interpolation$value ($label; slices $ids)" $propdict
        set all_ok 1
        set parts {}
        foreach xx $active_ids {
            set got [v04a_get "CONFIG.DAC_Interpolation_Mode${xx}" $rfdc]
            lappend parts "${xx}={$got}"
            if {![v04a_num_eq $got $value]} { set all_ok 0 }
        }
        v04a_log $fh "DAC interpolation readback ($label; after slices $ids): [join $parts { }]"
        if {$all_ok} { break }
    }
    v04a_checkpoint_all_tiles $fh $rfdc "after DAC interpolation$value ($label)"
    return $all_ok
}

proc v04a_report_state {fh rfdc label} {
    v04a_log $fh "## STATE: $label"
    v04a_report_sync_props $fh $rfdc $label
    set dac_parts [list "DAC active slices:"]
    foreach xx {00 02 10 12 20} {
        lappend dac_parts "${xx}_EN={[v04a_get CONFIG.DAC_Slice${xx}_Enable $rfdc]}"
        lappend dac_parts "${xx}_WIDTH={[v04a_get CONFIG.DAC_Data_Width${xx} $rfdc]}"
        lappend dac_parts "${xx}_INTERP={[v04a_get CONFIG.DAC_Interpolation_Mode${xx} $rfdc]}"
    }
    v04a_log $fh [join $dac_parts " "]
    v04a_checkpoint_all_tiles $fh $rfdc $label
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
    foreach syspin {user_sysref_adc user_sysref_dac} {
        set pin [lindex [get_bd_pins -quiet "$rfdc/$syspin"] 0]
        if {$pin eq ""} {
            v04a_log $fh "$syspin pin ABSENT"
        } else {
            v04a_log $fh "$syspin driven by {[v04a_pin_drivers $pin]}"
        }
    }
    v04a_log $fh ""
}

set failures {}
set warnings {}
set ::v04a_diag_results {}
set ::v04a_diag_solution ""
set ::v04a_pl_clock_before "<unknown>"
set ::v04a_pl_clock_preset_500 0
set ::v04a_expected_pl_clock ""
set ::v04a_expected_dac_interpolation ""
set ::v04a_adc_aclk_rewired_250 0
set ::v04a_user_sysref_source ""

v04a_log $fh "# V04 scratch RFDC apply v1.3 atomic-dict + MTS root-cause diagnostics (scratch project only) - Vivado [lindex [version] 1]"
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
if {[v04a_pl_clock_exists $rfdc]} {
    set ::v04a_pl_clock_before [v04a_get CONFIG.PL_Clock_Freq $rfdc]
} else {
    set ::v04a_pl_clock_before "<absent>"
}
v04a_log $fh "PL_Clock_Freq BEFORE = {$::v04a_pl_clock_before}"
set ::v04a_user_sysref_source [v04a_capture_user_sysref_source $rfdc]
v04a_log $fh "USER_SYSREF SOURCE CAPTURED = {$::v04a_user_sysref_source}"
v04a_checkpoint $fh $rfdc "BEFORE"
v04a_checkpoint_all_tiles $fh $rfdc "BEFORE"

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

# v1.3 ordering probe: if the live RFDC cell has PL_Clock_Freq, put it at
# the MTS base's 500 MHz common PL clock BEFORE the stage-2 transaction
# that flipped MTS in v1.2.  500 MHz is an integer multiple of both the
# target ADC AXIS clock (250 MHz) and the unchanged DAC AXIS clock
# (500 MHz).  If it is already 500 this is deliberately a logged no-op.
if {[v04a_pl_clock_exists $rfdc]} {
    if {[v04a_num_eq $::v04a_pl_clock_before 500.000]} {
        v04a_log $fh "PL CLOCK PRE-STAGE: already 500.000; no write needed"
    } else {
        set ::v04a_pl_clock_preset_500 \
            [v04a_set_pl_clock $fh $rfdc 500.000 "pre-stage-2 normalize"]
    }
    v04a_checkpoint $fh $rfdc "after PL clock pre-stage"
} else {
    v04a_log $fh "PL CLOCK PRE-STAGE: CONFIG.PL_Clock_Freq absent; continuing with clock/connectivity diagnostics only"
}

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

# If a datapath stage cleared MTS, run the v1.3 root-cause branches before
# validate so a successful branch is the state validate actually sees.
# PG269 allows different ADC/DAC AXIS clocks when the PL clock is a common
# integer multiple and PL SYSREF is captured in each AXIS domain, so the
# preferred branches keep ADC fabric 250 MHz + DAC fabric 500 MHz.  The
# equal-fabric DAC-250 branch is diagnostic until explicitly adopted.
if {[v04a_mts_true $rfdc]} {
    if {$::v04a_pl_clock_preset_500} {
        set ::v04a_diag_solution "PL500_PRESET_BEFORE_STAGE2"
        set ::v04a_expected_pl_clock 500.000
    } elseif {[v04a_pl_clock_exists $rfdc]} {
        set ::v04a_diag_solution "NO_MTS_FLIP"
        set ::v04a_expected_pl_clock [v04a_get CONFIG.PL_Clock_Freq $rfdc]
    } else {
        set ::v04a_diag_solution "NO_MTS_FLIP_NO_PL_CLOCK_PROPERTY"
    }
    lappend ::v04a_diag_results "$::v04a_diag_solution=PASS"
    v04a_log $fh "MTS DIAGNOSTIC SOLUTION=$::v04a_diag_solution (no restore branch needed)"
} else {
    lappend warnings "MTS was cleared during the datapath apply; v1.3 diagnostic branches attempted before validate (see CHECKPOINT and BRANCH RESULT lines)"
    v04a_log $fh "## MTS ROOT-CAUSE DIAGNOSTICS (final ADC datapath already applied)"
    v04a_report_sync_props $fh $rfdc "diagnostics entry"
    v04a_checkpoint_all_tiles $fh $rfdc "diagnostics entry"

    # D0: exact v1.2 all-at-once restore, now under the reported PL state.
    if {[v04a_restore_mts $fh $rfdc "D0 baseline pre-validate"]} {
        set ::v04a_diag_solution "BASELINE_RESTORE_AFTER_DATAPATH"
        if {[v04a_pl_clock_exists $rfdc]} {
            set ::v04a_expected_pl_clock [v04a_get CONFIG.PL_Clock_Freq $rfdc]
        }
        lappend ::v04a_diag_results "D0_BASELINE_RESTORE=PASS"
    } else {
        lappend ::v04a_diag_results "D0_BASELINE_RESTORE=FAIL"
    }

    # D1/D2: PL clock value, with both MTS groups forced through a real
    # false->true transition (v04a_try_pl_all retoggles DAC explicitly).
    if {$::v04a_diag_solution eq "" && [v04a_pl_clock_exists $rfdc]} {
        if {[v04a_try_pl_all $fh $rfdc 500.000 "D1 PL500 split ADC250/DAC500"]} {
            set ::v04a_diag_solution "PL500_SPLIT_FABRIC"
            set ::v04a_expected_pl_clock 500.000
            lappend ::v04a_diag_results "D1_PL500_SPLIT_FABRIC=PASS"
        } else {
            lappend ::v04a_diag_results "D1_PL500_SPLIT_FABRIC=FAIL"
            v04a_normalize_dac_mts_500 $fh $rfdc "D1"
            if {[v04a_mts_true $rfdc]} {
                set ::v04a_diag_solution "PL500_ADC_THEN_DAC_NORMALIZE"
                set ::v04a_expected_pl_clock 500.000
                lappend ::v04a_diag_results "D1_PL500_AFTER_DAC_NORMALIZE=PASS"
            }
        }
    }
    if {$::v04a_diag_solution eq "" && [v04a_pl_clock_exists $rfdc]} {
        if {[v04a_try_pl_all $fh $rfdc 250.000 "D2 PL250 split ADC250/DAC500"]} {
            set ::v04a_diag_solution "PL250_SPLIT_FABRIC"
            set ::v04a_expected_pl_clock 250.000
            lappend ::v04a_diag_results "D2_PL250_SPLIT_FABRIC=PASS"
        } else {
            if {[v04a_mts_kind_true $rfdc ADC]} {
                lappend ::v04a_diag_results "D2_PL250_ADC_ONLY=PASS_DAC_RETOGGLE_FAIL"
            } else {
                lappend ::v04a_diag_results "D2_PL250_SPLIT_FABRIC=FAIL"
            }
            v04a_normalize_dac_mts_500 $fh $rfdc "D2"
            if {[v04a_mts_true $rfdc]} {
                set ::v04a_diag_solution "PL250_ADC_THEN_PL500_DAC_NORMALIZE"
                set ::v04a_expected_pl_clock 500.000
                lappend ::v04a_diag_results "D2_AFTER_PL500_DAC_NORMALIZE=PASS"
            }
        }
    }

    # D3: cross-group sequencing (DAC MTS off -> ADC on -> DAC on).
    if {$::v04a_diag_solution eq ""} {
        v04a_normalize_dac_mts_500 $fh $rfdc "D3 entry"
        if {[v04a_restore_mts_sequence $fh $rfdc "D3 sequence at PL500/current"]} {
            set ::v04a_diag_solution "SEQUENCE_DAC_OFF_ADC_ON_DAC_ON_PL500"
            if {[v04a_pl_clock_exists $rfdc]} { set ::v04a_expected_pl_clock 500.000 }
            lappend ::v04a_diag_results "D3_SEQUENCE_PL500=PASS"
        } elseif {[v04a_pl_clock_exists $rfdc]} {
            lappend ::v04a_diag_results "D3_SEQUENCE_PL500=FAIL"
            v04a_set_pl_clock $fh $rfdc 250.000 "D3 sequence PL250 entry"
            if {[v04a_restore_mts_sequence $fh $rfdc "D3 sequence at PL250"]} {
                set ::v04a_diag_solution "SEQUENCE_DAC_OFF_ADC_ON_DAC_ON_PL250"
                set ::v04a_expected_pl_clock 250.000
                lappend ::v04a_diag_results "D3_SEQUENCE_PL250=PASS"
            } else {
                lappend ::v04a_diag_results "D3_SEQUENCE_PL250=FAIL"
                v04a_normalize_dac_mts_500 $fh $rfdc "D3"
            }
        } else {
            lappend ::v04a_diag_results "D3_SEQUENCE=FAIL"
            v04a_normalize_dac_mts_500 $fh $rfdc "D3"
        }
    }

    # D4: connected-clock dependency.  Move only the RFDC ADC AXIS clock
    # pins to clkRFdiv2/250 MHz (the V07 direction), then retry MTS.
    if {$::v04a_diag_solution eq ""} {
        v04a_normalize_dac_mts_500 $fh $rfdc "D4 entry"
        if {[v04a_rewire_adc_aclk_250 $fh $rfdc]} {
            set ::v04a_adc_aclk_rewired_250 1
            v04a_report_state $fh $rfdc "AFTER ADC ACLK REWIRE (pre-restore)"
            if {[v04a_restore_mts $fh $rfdc "D4 ADC aclk250 baseline"]} {
                set ::v04a_diag_solution "ADC_ACLK250_BASELINE"
                if {[v04a_pl_clock_exists $rfdc]} {
                    set ::v04a_expected_pl_clock [v04a_get CONFIG.PL_Clock_Freq $rfdc]
                }
                lappend ::v04a_diag_results "D4_ADC_ACLK250_BASELINE=PASS"
            } elseif {[v04a_pl_clock_exists $rfdc] && \
                      [v04a_try_pl_all $fh $rfdc 500.000 "D4 ADC aclk250 + PL500"]} {
                set ::v04a_diag_solution "ADC_ACLK250_PL500"
                set ::v04a_expected_pl_clock 500.000
                lappend ::v04a_diag_results "D4_ADC_ACLK250_PL500=PASS"
            } elseif {[v04a_pl_clock_exists $rfdc] && \
                      [v04a_try_pl_all $fh $rfdc 250.000 "D4 ADC aclk250 + PL250"]} {
                set ::v04a_diag_solution "ADC_ACLK250_PL250"
                set ::v04a_expected_pl_clock 250.000
                lappend ::v04a_diag_results "D4_ADC_ACLK250_PL250=PASS"
            } else {
                if {[v04a_mts_kind_true $rfdc ADC]} {
                    lappend ::v04a_diag_results "D4_ADC_ACLK250_ADC_ONLY=PASS_DAC_FAIL"
                } else {
                    lappend ::v04a_diag_results "D4_ADC_ACLK250=FAIL"
                }
                v04a_normalize_dac_mts_500 $fh $rfdc "D4"
                if {[v04a_mts_true $rfdc]} {
                    set ::v04a_diag_solution "ADC_ACLK250_AFTER_PL500_DAC_NORMALIZE"
                    if {[v04a_pl_clock_exists $rfdc]} { set ::v04a_expected_pl_clock 500.000 }
                    lappend ::v04a_diag_results "D4_ADC_ACLK250_AFTER_DAC_NORMALIZE=PASS"
                } elseif {[v04a_restore_adc_aclk_500 $fh $rfdc]} {
                    set ::v04a_adc_aclk_rewired_250 0
                    lappend ::v04a_diag_results "D4_ADC_ACLK_RESTORED_500=PASS"
                } else {
                    lappend ::v04a_diag_results "D4_ADC_ACLK_RESTORED_500=FAIL"
                    lappend warnings "D4 failed and ADC AXIS clock pins could not be restored to 500 MHz; D5/D6 are therefore not fully isolated from the 250 MHz clock-pin state"
                }
            }
        } else {
            lappend ::v04a_diag_results "D4_ADC_ACLK250=REWIRE_ERROR"
        }
    }

    # D5: equal-fabric probe.  DAC interpolation 2 on every active DAC
    # slice makes DAC fabric 250 MHz like the ADCs.  Success here proves
    # a workaround/root-cause class, but changes the HIL DAC contract, so
    # it is labelled PASS-DIAGNOSTIC at the end, not production PASS.
    if {$::v04a_diag_solution eq ""} {
        v04a_normalize_dac_mts_500 $fh $rfdc "D5 entry"
        if {[v04a_set_dac_interpolation $fh $rfdc 2 "D5 equal-fabric"]} {
            set dac250_ok 0
            set dac250_pl ""
            if {[v04a_pl_clock_exists $rfdc] && \
                [v04a_try_pl_all $fh $rfdc 250.000 "D5 DAC250 + PL250"]} {
                set dac250_ok 1
                set dac250_pl 250.000
                lappend ::v04a_diag_results "D5_DAC250_PL250=PASS"
                # Distinguish "PL must equal fabric" from "ADC/DAC fabric
                # must match": force an ADC false->true at PL500 as well.
                v04a_set_pl_clock $fh $rfdc 500.000 "D5 DAC250 PL500 distinguish"
                v04a_set_mts_kind $fh $rfdc ADC false "D5 DAC250 PL500 ADC retoggle off"
                v04a_set_mts_kind $fh $rfdc ADC true "D5 DAC250 PL500 ADC retoggle on"
                if {[v04a_mts_true $rfdc]} {
                    set dac250_pl 500.000
                    lappend ::v04a_diag_results "D5_DAC250_PL500_ALSO=PASS"
                } elseif {[v04a_try_pl_all $fh $rfdc 250.000 "D5 DAC250 recover PL250"]} {
                    set dac250_pl 250.000
                    lappend ::v04a_diag_results "D5_DAC250_PL500=FAIL_PL250_RECOVERED"
                } else {
                    set dac250_ok 0
                    lappend ::v04a_diag_results "D5_DAC250_PL500=FAIL_PL250_RECOVERY_FAIL"
                }
            } elseif {[v04a_pl_clock_exists $rfdc] && \
                      [v04a_try_pl_all $fh $rfdc 500.000 "D5 DAC250 + PL500"]} {
                set dac250_ok 1
                set dac250_pl 500.000
                lappend ::v04a_diag_results "D5_DAC250_PL500=PASS"
            } elseif {![v04a_pl_clock_exists $rfdc] && \
                      [v04a_restore_mts $fh $rfdc "D5 DAC250 no PL property"]} {
                set dac250_ok 1
                lappend ::v04a_diag_results "D5_DAC250_NO_PL_PROPERTY=PASS"
            } else {
                lappend ::v04a_diag_results "D5_DAC250_EQUAL_FABRIC=FAIL"
            }
            if {$dac250_ok} {
                set pl_label "NONE"
                if {$dac250_pl ne ""} { set pl_label [format %.0f $dac250_pl] }
                set ::v04a_diag_solution "DAC250_EQUAL_FABRIC_PL${pl_label}"
                set ::v04a_expected_pl_clock $dac250_pl
                set ::v04a_expected_dac_interpolation 2
                lappend warnings "MTS restored only in the DAC250 equal-fabric diagnostic branch; adopting DAC interpolation 2 / DAC AXIS 250 MHz is a separate V04/V07 production decision"
            } else {
                v04a_set_dac_interpolation $fh $rfdc 1 "D5 revert"
                v04a_normalize_dac_mts_500 $fh $rfdc "D5 revert"
            }
        } else {
            lappend ::v04a_diag_results "D5_DAC250_EQUAL_FABRIC=SET_ERROR"
            v04a_set_dac_interpolation $fh $rfdc 1 "D5 error revert"
            v04a_normalize_dac_mts_500 $fh $rfdc "D5 error revert"
        }
    }

    # D6: last property probe, always reverted.  ADC Data_Width=4 with
    # decimation 2 should compute fabric 500 MHz again; if MTS restores
    # only here, the dependency is tied to ADC fabric/PL equality at
    # 500 MHz rather than decimation itself.  Width 8 is restored so the
    # persisted datapath assertions still test the V04 target.
    if {$::v04a_diag_solution eq ""} {
        v04a_log $fh "D6 ADC WIDTH4 PROBE: temporary Data_Width=4 + decimation2 (expect ADC fabric 500 MHz)"
        v04a_set_dict $fh $rfdc "D6 rate: width4 + decimation2 (all pairs)" \
            [v04a_build_dict {{Data_Width 4} {Decimation_Mode 2}} $pair_ids]
        v04a_decimation_is_2 $fh $rfdc $pair_ids "D6 width4"
        v04a_checkpoint_all_tiles $fh $rfdc "D6 width4 pre-restore"
        set width4_ok [v04a_restore_mts $fh $rfdc "D6 width4 baseline"]
        if {!$width4_ok && [v04a_pl_clock_exists $rfdc]} {
            set width4_ok [v04a_try_pl_all $fh $rfdc 500.000 "D6 width4 + PL500"]
        }
        lappend ::v04a_diag_results "D6_ADC_WIDTH4_FABRIC500=[expr {$width4_ok ? {PASS} : {FAIL}}]"
        if {$width4_ok} {
            lappend warnings "ADC MTS restored only in the temporary Data_Width=4/fabric-500 probe; width8/250 MHz was restored, so this is root-cause evidence, not a V04 pass"
        }
        v04a_log $fh "D6 REVERT: Data_Width=8 + decimation2 (expect ADC fabric 250 MHz; MTS may flip again)"
        v04a_set_dict $fh $rfdc "D6 revert rate: width8 + decimation2 (all pairs)" \
            [v04a_build_dict $rate_groups $pair_ids]
        v04a_decimation_is_2 $fh $rfdc $pair_ids "D6 revert width8"
        v04a_normalize_dac_mts_500 $fh $rfdc "D6 revert"
        v04a_checkpoint_all_tiles $fh $rfdc "D6 after revert"
    }

    foreach result $::v04a_diag_results {
        v04a_log $fh "MTS DIAGNOSTIC RESULT: $result"
    }
    if {$::v04a_diag_solution eq ""} {
        v04a_log $fh "MTS DIAGNOSTIC SOLUTION=NONE (all branches failed; see BRANCH RESULT lines above)"
        lappend failures "Multi_Tile_Sync could not be restored by any v1.3 diagnostic branch before validate"
    } else {
        v04a_log $fh "MTS DIAGNOSTIC SOLUTION=$::v04a_diag_solution expected_PL_Clock_Freq={$::v04a_expected_pl_clock} expected_DAC_interpolation={$::v04a_expected_dac_interpolation} adc_aclk_rewired_250=$::v04a_adc_aclk_rewired_250"
    }
    v04a_ensure_user_sysref_connected $fh $rfdc "after MTS diagnostics"
    v04a_report_state $fh $rfdc "AFTER MTS DIAGNOSTICS (pre-validate)"
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
    if {[v04a_restore_mts_with_sequence $fh $rfdc "after validate #1"]} {
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
            if {![v04a_restore_mts_with_sequence $fh $rfdc "final, after validate #2"]} {
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
foreach result $::v04a_diag_results {
    v04a_log $fh "MTS DIAGNOSTIC RESULT (persisted): $result"
}
v04a_log $fh "MTS DIAGNOSTIC SOLUTION (persisted check)=$::v04a_diag_solution"
if {$::v04a_expected_pl_clock ne ""} {
    set got_pl [v04a_get CONFIG.PL_Clock_Freq $rfdc]
    if {![v04a_num_eq $got_pl $::v04a_expected_pl_clock]} {
        lappend failures "PL_Clock_Freq: got {$got_pl}, expected {$::v04a_expected_pl_clock} from solution $::v04a_diag_solution"
        v04a_log $fh "ASSERT FAIL CONFIG.PL_Clock_Freq = {$got_pl} (expected {$::v04a_expected_pl_clock})"
    }
}
if {$::v04a_expected_dac_interpolation ne ""} {
    foreach xx {00 02 10 12 20} {
        set got_dac_interp [v04a_get "CONFIG.DAC_Interpolation_Mode${xx}" $rfdc]
        if {![v04a_num_eq $got_dac_interp $::v04a_expected_dac_interpolation]} {
            lappend failures "DAC_Interpolation_Mode${xx}: got {$got_dac_interp}, expected {$::v04a_expected_dac_interpolation} from solution $::v04a_diag_solution"
            v04a_log $fh "ASSERT FAIL CONFIG.DAC_Interpolation_Mode${xx} = {$got_dac_interp} (expected {$::v04a_expected_dac_interpolation})"
        }
    }
    foreach tile {0 1 2} {
        set got_dac_fabric [v04a_get "CONFIG.DAC${tile}_Fabric_Freq" $rfdc]
        if {![v04a_num_eq $got_dac_fabric 250.000]} {
            lappend failures "DAC${tile}_Fabric_Freq: got {$got_dac_fabric}, expected 250.000 in DAC250 diagnostic branch"
            v04a_log $fh "ASSERT FAIL CONFIG.DAC${tile}_Fabric_Freq = {$got_dac_fabric} (expected 250.000)"
        }
    }
}
if {$::v04a_adc_aclk_rewired_250} {
    foreach clkpin {m0_axis_aclk m1_axis_aclk} {
        set pin [lindex [get_bd_pins -quiet "$rfdc/$clkpin"] 0]
        set drivers [v04a_pin_drivers $pin]
        if {[lsearch -glob $drivers *clkRFdiv2] < 0} {
            lappend failures "$clkpin is not driven by clkRFdiv2 after reopen (drivers: $drivers)"
            v04a_log $fh "ASSERT FAIL $clkpin drivers={$drivers} (expected *clkRFdiv2)"
        }
    }
}
foreach syspin {user_sysref_adc user_sysref_dac} {
    set pin [lindex [get_bd_pins -quiet "$rfdc/$syspin"] 0]
    set drivers [v04a_pin_drivers $pin]
    if {$pin eq "" || [llength $drivers] == 0} {
        lappend failures "$syspin is absent or unconnected after reopen (pin={$pin}, drivers={$drivers}); MTS property values alone are not a pass"
        v04a_log $fh "ASSERT FAIL $syspin pin={$pin} drivers={$drivers} (expected connected)"
    }
}
if {[info exists ::v04a_before_tiles]} {
    dict for {prop expected} $::v04a_before_tiles {
        if {$expected eq "<unavailable>"} { continue }
        if {[string match "DAC250*" $::v04a_diag_solution] && \
            ($prop eq "CONFIG.DAC0_Fabric_Freq" || $prop eq "CONFIG.DAC1_Fabric_Freq")} {
            v04a_log $fh "INVARIANT WAIVED $prop: DAC250 diagnostic branch intentionally changes 500.000 -> 250.000"
            continue
        }
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
if {[string match "DAC250*" $::v04a_diag_solution]} {
    if {$validate_rc} {
        v04a_log $fh "V04 SCRATCH CONFIG RESULT=PASS-DIAGNOSTIC solution=$::v04a_diag_solution (MTS persists only with DAC interpolation 2 / DAC fabric 250 MHz; production adoption is a separate V04/V07 decision; full-BD validate still FAILS until V07 rewires clocks/streams/SYSREF)"
    } else {
        v04a_log $fh "V04 SCRATCH CONFIG RESULT=PASS-DIAGNOSTIC solution=$::v04a_diag_solution (MTS persists only with DAC interpolation 2 / DAC fabric 250 MHz; production adoption is a separate V04/V07 decision; full-BD validate also passed in scratch)"
    }
    set final_puts "V04 SCRATCH APPLY PASS-DIAGNOSTIC solution=$::v04a_diag_solution (report: $out_file)"
} elseif {$validate_rc} {
    v04a_log $fh "V04 SCRATCH CONFIG RESULT=PASS solution=$::v04a_diag_solution (full-BD validate still FAILS as expected until V07 moves ADC streams to 250 MHz and replaces the MTS capture path)"
    set final_puts "V04 SCRATCH APPLY PASS solution=$::v04a_diag_solution (report: $out_file)"
} else {
    v04a_log $fh "V04 SCRATCH CONFIG RESULT=PASS solution=$::v04a_diag_solution (full-BD validate also passed in scratch)"
    set final_puts "V04 SCRATCH APPLY PASS solution=$::v04a_diag_solution (report: $out_file)"
}
v04a_log $fh "Input project untouched: $input_xpr"
v04a_log $fh "Scratch project (deletable): $scratch_xpr"
close $fh
close_project
puts $final_puts
