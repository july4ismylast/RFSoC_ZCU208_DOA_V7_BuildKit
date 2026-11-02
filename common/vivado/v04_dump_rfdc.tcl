# Stage V04: read-only RFDC property/stream dump from the DOA work project.
# Purpose: prove the exact 2023.2 RFDC Tcl property names + allowed enum
# values (mixer type/mode, decimation, data type, Nyquist/calibration)
# BEFORE any V07 "apply" Tcl is written. This script never modifies or
# saves the project or BD.
#
# Usage (from the repo root, after step07 created the work project):
#   <Vivado 2023.2>/bin/vivado.bat -mode batch -nojournal -nolog -source common/vivado/v04_dump_rfdc.tcl
# Output: build/output/v04_rfdc_properties_before.rpt
# WORK_XPR may be overridden in the environment, same convention as step07.

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ../..]]
cd $repo_root

if {[info exists ::env(WORK_XPR)]} {
    set work_xpr [file normalize $::env(WORK_XPR)]
} else {
    set work_xpr [file normalize [file join $repo_root build \
        vivado doa_v7_zcu208 doa_v7_zcu208.xpr]]
}
set out_dir [file join $repo_root build output]
set out_file [file join $out_dir v04_rfdc_properties_before.rpt]
file mkdir $out_dir

if {![file exists $work_xpr]} {
    error "V04 dump: DOA work project not found: $work_xpr (run: python scripts/run_steps.py run step07 --mode no-dac first)"
}

open_project $work_xpr

set bd_file [lindex [get_files -quiet */mts.bd] 0]
if {$bd_file eq ""} {
    error "V04 dump: mts.bd not found in work project $work_xpr"
}
open_bd_design $bd_file

set rfdc [lindex [get_bd_cells -hierarchical -quiet \
    -filter {VLNV =~ *usp_rf_data_converter*}] 0]
if {$rfdc eq ""} {
    error "V04 dump: no usp_rf_data_converter cell found in $bd_file"
}

set fh [open $out_file w]
puts $fh "# V04 RFDC dump (read-only) - Vivado [lindex [version] 1]"
puts $fh "# project=$work_xpr"
puts $fh "# bd=$bd_file"
puts $fh "# cell=$rfdc vlnv=[get_property VLNV $rfdc]"
puts $fh ""

# --- Current CONFIG values (ADC tiles/slices + clocking keys we will touch) ---
puts $fh "## CONFIG VALUES"
foreach prop [lsort [list_property $rfdc]] {
    if {![string match "CONFIG.*" $prop]} { continue }
    if {[catch {set val [get_property $prop $rfdc]}]} { continue }
    puts $fh "$prop = {$val}"
}
puts $fh ""

# --- Allowed enum values for the properties V04/V07 cares about ---
puts $fh "## ALLOWED VALUES (representative slice 00 + tile/global keys)"
set interesting {
    CONFIG.ADC_Data_Type00 CONFIG.ADC_Mixer_Type00 CONFIG.ADC_Mixer_Mode00
    CONFIG.ADC_Decimation_Mode00 CONFIG.ADC_Data_Width00
    CONFIG.ADC_Coarse_Mixer_Freq00 CONFIG.ADC_NCO_Freq00
    CONFIG.ADC_Nyquist_Zone00 CONFIG.ADC_Calibration_Mode00
    CONFIG.ADC0_Enable CONFIG.ADC_Sampling_Rate0 CONFIG.ADC_Fabric_Freq0
    CONFIG.ADC_Refclk_Freq0 CONFIG.ADC_Outclk_Freq0 CONFIG.ADC_Multi_Tile_Sync0
    CONFIG.ADC_Mixer_Type02 CONFIG.ADC_Mixer_Mode02 CONFIG.ADC_Decimation_Mode02
    CONFIG.ADC_Mixer_Type10 CONFIG.ADC_Mixer_Mode10 CONFIG.ADC_Decimation_Mode10
    CONFIG.ADC_Mixer_Type12 CONFIG.ADC_Mixer_Mode12 CONFIG.ADC_Decimation_Mode12
}
# Also catch any property whose name mentions these topics, in case the
# 2023.2 spelling differs from the list above.
foreach prop [lsort [list_property $rfdc]] {
    foreach pat {*Mixer* *Decimation* *Data_Type* *Nyquist* *Calibration* *NCO*} {
        if {[string match "CONFIG.ADC$pat" $prop] && [lsearch $interesting $prop] < 0} {
            lappend interesting $prop
            break
        }
    }
}
foreach prop $interesting {
    if {[lsearch [list_property $rfdc] $prop] < 0} { continue }
    if {[catch {set allowed [list_property_value $prop $rfdc]} err]} {
        puts $fh "$prop : <list_property_value failed: $err>"
    } else {
        puts $fh "$prop : {$allowed}"
    }
}
puts $fh ""

# --- Stream + clock interface pins as they exist before reconfiguration ---
puts $fh "## RFDC INTERFACE PINS"
foreach pin [lsort [get_bd_intf_pins -quiet -of_objects $rfdc]] {
    puts $fh "[get_property NAME $pin] vlnv=[get_property VLNV $pin] mode=[get_property MODE $pin]"
}
puts $fh ""
puts $fh "## RFDC CLOCK PINS (FREQ_HZ)"
foreach pin [lsort [get_bd_pins -quiet -of_objects $rfdc]] {
    if {[get_property TYPE $pin] ne "clk"} { continue }
    set f ""
    catch {set f [get_property FREQ_HZ $pin]}
    puts $fh "[get_property NAME $pin] dir=[get_property DIR $pin] FREQ_HZ={$f}"
}
puts $fh ""

# --- clocktreeMTS output plan (250 MHz domain must be confirmed here) ---
set wiz [lindex [get_bd_cells -hierarchical -quiet \
    -filter {NAME =~ *clocktreeMTS*}] 0]
if {$wiz ne ""} {
    puts $fh "## clocktreeMTS ($wiz)"
    foreach prop [lsort [list_property $wiz]] {
        if {![regexp {^CONFIG\.(NUM_OUT_CLKS|CLKOUT[0-9]+_REQUESTED_OUT_FREQ|PRIM_IN_FREQ)} $prop]} { continue }
        if {[catch {set val [get_property $prop $wiz]}]} { continue }
        puts $fh "$prop = {$val}"
    }
}

close $fh
puts "V04 DUMP wrote $out_file"
puts "V04 DUMP PASS (read-only; project/BD were not modified)"
