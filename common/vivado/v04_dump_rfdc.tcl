# Stage V04: read-only RFDC property/stream dump from the DOA work project.
#
# First run (2026-11-02, user PC) proved the RFDC 2.6 property spellings and
# the current MTS values, but also proved that list_property_value returns {}
# for BD CONFIG.* properties (they are string-typed Vivado properties; the
# enum labels live in the IP-XACT component.xml).  This revised dump is
# therefore compact and targeted:
#   * current values for ADC tiles 0/1 and datapath slices 00..03/10..13;
#   * the component.xml parameter blocks + choice enumerations for the V04
#     enums (data type, decimation, mixer mode/type, Nyquist, CalOpt);
#   * RFDC m*_axis interface parameters and physical TDATA widths;
#   * the real MTSclkwiz output frequencies inside clocktreeMTS.
# Set V04_DUMP_FULL=1 to also append every CONFIG.* value.
#
# This script never modifies or saves the project or BD.
# Usage (from the repo root, after step07 created the work project):
#   <Vivado 2023.2>/bin/vivado -mode batch -nojournal -nolog -source common/vivado/v04_dump_rfdc.tcl
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
    error "V04 dump: DOA work project not found: $work_xpr (run step07 first)"
}

# Pinned VLNV table (comparison only; a mismatch is reported, not hidden).
source [file join $repo_root config ip_versions.tcl]

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
set rfdc_vlnv [get_property VLNV $rfdc]

proc v04_get {prop object} {
    if {[catch {set value [get_property $prop $object]}]} { return "<unavailable>" }
    return $value
}

proc v04_clip {line} {
    if {[string length $line] > 600} {
        return "[string range $line 0 599] ...<clipped>"
    }
    return $line
}

set fh [open $out_file w]
puts $fh "# V04 RFDC dump v2.1 streaming (read-only) - Vivado [lindex [version] 1]"
puts $fh "# project=$work_xpr"
puts $fh "# bd=$bd_file"
puts $fh "# cell=$rfdc vlnv=$rfdc_vlnv"
if {$rfdc_vlnv eq $::IPVLNV(rfdc)} {
    puts $fh "# lock: MATCHES config/ip_versions.tcl"
} else {
    puts $fh "# lock: MISMATCH - config/ip_versions.tcl pins $::IPVLNV(rfdc)"
}
puts $fh ""

# --- Tile-level values for the two used ADC tiles ---------------------------
puts $fh "## ADC TILE PROPERTIES (tiles 0/1)"
foreach tile {0 1} {
    foreach suffix {Enable Sampling_Rate Refclk_Freq Fabric_Freq Outclk_Freq \
                    PLL_Enable Clock_Source Clock_Dist Multi_Tile_Sync Band} {
        set prop "CONFIG.ADC${tile}_${suffix}"
        puts $fh "$prop = {[v04_get $prop $rfdc]}"
    }
}
puts $fh ""

# --- Per-slice datapath values (all eight slices of tiles 0/1) --------------
puts $fh "## ADC DATAPATH PROPERTIES (slices 00..03, 10..13)"
set slice_props {Slice%s_Enable Data_Type%s Data_Width%s Decimation_Mode%s \
    Mixer_Mode%s Mixer_Type%s Coarse_Mixer_Freq%s NCO_Freq%s NCO_Phase%s \
    Neg_Quadrature%s Nyquist%s CalOpt_Mode%s Bypass_BG_Cal%s Dither%s}
foreach slice {00 01 02 03 10 11 12 13} {
    puts $fh "-- slice $slice"
    foreach pattern $slice_props {
        set prop "CONFIG.ADC_[format $pattern $slice]"
        puts $fh "  $prop = {[v04_get $prop $rfdc]}"
    }
}
puts $fh ""

# --- IP-XACT enum evidence ---------------------------------------------------
# v2.1: stream the XML in two line-by-line passes and print progress to the
# console.  (v2 read/split the whole component.xml and rescanned the line
# list once per parameter, which can look hung for minutes on the RFDC XML.)
puts $fh "## IP-XACT PARAMETER CHOICES"
puts "V04 DUMP: locating RFDC IP definition / component.xml ..."
set ipdef ""
set xml_file ""
catch {set ipdef [get_property IPDEF $rfdc]}
if {$ipdef ne ""} {
    catch {set xml_file [get_property XML_FILE_NAME $ipdef]}
}
if {$xml_file eq ""} {
    set ipdef2 ""
    catch {set ipdef2 [lindex [get_ipdefs -all -quiet -filter "VLNV == $rfdc_vlnv"] 0]}
    if {$ipdef2 eq ""} {
        catch {set ipdef2 [lindex [get_ipdefs -all -quiet $rfdc_vlnv] 0]}
    }
    if {$ipdef2 ne ""} {
        set ipdef $ipdef2
        catch {set xml_file [get_property XML_FILE_NAME $ipdef]}
    }
}
puts $fh "ipdef={$ipdef}"
puts $fh "component_xml={$xml_file}"
flush $fh
if {$xml_file ne "" && [file exists $xml_file]} {
    puts $fh "component_xml_bytes=[file size $xml_file]"
    set target_params {ADC_Data_Type00 ADC_Data_Width00 ADC_Decimation_Mode00 \
        ADC_Mixer_Mode00 ADC_Mixer_Type00 ADC_Coarse_Mixer_Freq00 \
        ADC_Nyquist00 ADC_CalOpt_Mode00 ADC_Slice00_Enable}

    # Pass 1: stream once, printing +/- context around every target
    # parameter name and collecting the choiceRef(s) each parameter uses.
    puts "V04 DUMP: component.xml pass 1/2 (parameter blocks) ..."
    array set param_seen {}
    array set param_refs {}
    set prev_lines [list "" ""]
    set pending {}
    set line_no 0
    set xfh [open $xml_file r]
    while {[gets $xfh line] >= 0} {
        incr line_no
        set trimmed [string trim $line]
        if {[regexp {choiceRef="([^"]+)"} $line -> line_ref]} {
            set has_ref 1
        } else {
            set has_ref 0
            set line_ref ""
        }
        # A new <...:name> element ends earlier look-ahead windows, so a
        # neighbouring parameter cannot steal this parameter's choiceRef.
        if {[regexp {<[^>]*:name>} $line]} { set pending {} }
        # Service look-ahead windows opened by earlier parameter hits.
        if {[llength $pending] > 0} {
            puts $fh "  [v04_clip $trimmed]"
            set still_pending {}
            foreach item $pending {
                lassign $item pparam remaining
                if {$has_ref && [lsearch -exact $param_refs($pparam) $line_ref] < 0} {
                    lappend param_refs($pparam) $line_ref
                }
                incr remaining -1
                if {$remaining > 0} { lappend still_pending [list $pparam $remaining] }
            }
            set pending $still_pending
        }
        # Start a new context window on a target parameter name.
        foreach param $target_params {
            if {[string first ">${param}<" $line] < 0} { continue }
            set param_seen($param) 1
            if {![info exists param_refs($param)]} { set param_refs($param) {} }
            puts $fh "--- parameter $param (xml line $line_no)"
            foreach prev $prev_lines {
                if {$prev ne ""} { puts $fh "  [v04_clip [string trim $prev]]" }
            }
            puts $fh "  [v04_clip $trimmed]"
            if {$has_ref && [lsearch -exact $param_refs($param) $line_ref] < 0} {
                lappend param_refs($param) $line_ref
            }
            lappend pending [list $param 8]
            break
        }
        set prev_lines [list [lindex $prev_lines 1] $line]
    }
    close $xfh
    puts $fh "component_xml_lines=$line_no"
    foreach param $target_params {
        if {![info exists param_seen($param)]} {
            puts $fh "--- parameter $param"
            puts $fh "  <parameter name not found as an XML element>"
        } else {
            puts $fh "parameter $param choiceRefs={$param_refs($param)}"
        }
    }
    flush $fh

    # Pass 2: stream again and print only the referenced choice definitions
    # (enumeration value -> GUI label).
    set needed_refs {}
    foreach param $target_params {
        if {![info exists param_refs($param)]} { continue }
        foreach ref $param_refs($param) {
            if {[lsearch -exact $needed_refs $ref] < 0} { lappend needed_refs $ref }
        }
    }
    puts "V04 DUMP: component.xml pass 2/2 ([llength $needed_refs] choice definitions) ..."
    if {[llength $needed_refs] == 0} {
        puts $fh "<no choiceRef found for the target parameters>"
    } else {
        array set choice_done {}
        set capture_ref ""
        set capture_left 0
        set xfh [open $xml_file r]
        while {[gets $xfh line] >= 0} {
            if {$capture_ref ne ""} {
                puts $fh "    [v04_clip [string trim $line]]"
                incr capture_left -1
                if {$capture_left <= 0 || [string match "*</*choice>*" $line]} {
                    set capture_ref ""
                }
                continue
            }
            foreach ref $needed_refs {
                if {[info exists choice_done($ref)]} { continue }
                if {[string first ">${ref}<" $line] < 0} { continue }
                set choice_done($ref) 1
                puts $fh "choiceRef=$ref definition:"
                puts $fh "    [v04_clip [string trim $line]]"
                set capture_ref $ref
                set capture_left 59
                break
            }
        }
        close $xfh
        foreach ref $needed_refs {
            if {![info exists choice_done($ref)]} {
                puts $fh "choiceRef=$ref definition: <not found>"
            }
        }
    }
    flush $fh
} else {
    puts $fh "<component.xml not located; enum labels still unproven>"
    flush $fh
}
puts $fh ""
puts "V04 DUMP: RFDC interface/clock pins ..."

# --- RFDC stream interfaces + physical widths --------------------------------
puts $fh "## RFDC INTERFACE PINS"
foreach pin [lsort [get_bd_intf_pins -quiet -of_objects $rfdc]] {
    set pname [get_property NAME $pin]
    puts $fh "$pname vlnv=[v04_get VLNV $pin] mode=[v04_get MODE $pin]"
    if {[string match "m*_axis" $pname]} {
        foreach prop [lsort [list_property $pin]] {
            if {![string match "CONFIG.*" $prop]} { continue }
            puts $fh "  $prop = {[v04_get $prop $pin]}"
        }
        foreach ppin [lsort [get_bd_pins -quiet "$rfdc/${pname}_tdata"]] {
            if {[get_property NAME $ppin] eq "${pname}_tdata"} {
                puts $fh "  tdata LEFT=[v04_get LEFT $ppin] RIGHT=[v04_get RIGHT $ppin]"
            }
        }
    }
}
puts $fh ""
puts $fh "## RFDC CLOCK PINS (FREQ_HZ as stored; may be empty until validate)"
foreach pin [lsort [get_bd_pins -quiet -of_objects $rfdc]] {
    if {[get_property TYPE $pin] ne "clk"} { continue }
    puts $fh "[get_property NAME $pin] dir=[v04_get DIR $pin] FREQ_HZ={[v04_get FREQ_HZ $pin]}"
}
puts $fh ""

# --- MTSclkwiz (inside clocktreeMTS hierarchy) -------------------------------
set wiz [lindex [get_bd_cells -hierarchical -quiet -filter {NAME == MTSclkwiz}] 0]
if {$wiz eq ""} {
    set wiz [lindex [get_bd_cells -hierarchical -quiet -filter {VLNV =~ *clk_wiz*}] 0]
}
puts $fh "## MTSclkwiz ({$wiz})"
if {$wiz ne ""} {
    foreach prop [lsort [list_property $wiz]] {
        if {![regexp {^CONFIG\.(NUM_OUT_CLKS|CLKOUT[0-9]+_REQUESTED_OUT_FREQ|CLKOUT[0-9]+_USED|PRIM_IN_FREQ)} $prop]} { continue }
        puts $fh "$prop = {[v04_get $prop $wiz]}"
    }
} else {
    puts $fh "<clock wizard cell not found>"
}
puts $fh ""

# --- Optional full CONFIG dump ----------------------------------------------
if {[info exists ::env(V04_DUMP_FULL)] && $::env(V04_DUMP_FULL) eq "1"} {
    puts $fh "## FULL CONFIG VALUES"
    foreach prop [lsort [list_property $rfdc]] {
        if {![string match "CONFIG.*" $prop]} { continue }
        puts $fh "$prop = {[v04_get $prop $rfdc]}"
    }
}

close $fh
puts "V04 DUMP wrote $out_file"
puts "V04 DUMP PASS (read-only; project/BD were not modified)"
