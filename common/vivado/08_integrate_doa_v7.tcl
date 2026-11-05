set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir common.tcl]
# Emit a diagnostic inventory before editing the base BD. This is captured in
# the stage log and in build/output so the board-specific map can be completed
# from actual Vivado object names instead of guessed paths.
proc doa_inventory_value {object property} {
    if {[catch {set value [get_property $property $object]}]} { return "<unavailable>" }
    return [string map [list "\n" " " "\r" " "] $value]
}
proc doa_inventory_emit {channel line} {
    puts $channel $line
    puts $line
}
proc doa_dump_base_bd_inventory {path} {
    set channel [open $path w]
    doa_inventory_emit $channel "=== BASE BD INVENTORY BEGIN ==="
    if {[catch {set cells [get_bd_cells -hier]} message]} {
        doa_inventory_emit $channel "ERROR listing BD cells: $message"
        close $channel
        return
    }
    foreach cell $cells {
        doa_inventory_emit $channel "CELL $cell VLNV=[doa_inventory_value $cell VLNV]"
        if {[catch {set interfaces [get_bd_intf_pins -quiet -of_objects $cell]}]} { set interfaces {} }
        foreach pin $interfaces {
            set net ""
            catch {set net [lindex [get_bd_intf_nets -quiet -of_objects $pin] 0]}
            set peers ""
            if {$net ne ""} {
                catch {
                    set endpoints [get_bd_intf_pins -quiet -of_objects $net]
                    set peers [join $endpoints ","]
                }
            }
            doa_inventory_emit $channel "  INTF $pin MODE=[doa_inventory_value $pin MODE] VLNV=[doa_inventory_value $pin VLNV] PROTOCOL=[doa_inventory_value $pin CONFIG.PROTOCOL] DATA_WIDTH=[doa_inventory_value $pin CONFIG.DATA_WIDTH] NET=$net PEERS=$peers"
        }
        if {[catch {set pins [get_bd_pins -quiet -of_objects $cell]}]} { set pins {} }
        foreach pin $pins {
            set pin_name [doa_inventory_value $pin NAME]
            if {![regexp -nocase {(clk|clock|reset|rst|irq|interrupt)} $pin_name]} { continue }
            set net ""
            catch {set net [lindex [get_bd_nets -quiet -of_objects $pin] 0]}
            set peers ""
            if {$net ne ""} {
                catch {
                    set endpoints [get_bd_pins -quiet -of_objects $net]
                    set peers [join $endpoints ","]
                }
            }
            doa_inventory_emit $channel "  PIN $pin DIR=[doa_inventory_value $pin DIR] TYPE=[doa_inventory_value $pin TYPE] NET=$net PEERS=$peers"
        }
    }
    foreach port [get_bd_intf_ports -quiet] {
        doa_inventory_emit $channel "TOP_INTF $port MODE=[doa_inventory_value $port MODE] VLNV=[doa_inventory_value $port VLNV] PROTOCOL=[doa_inventory_value $port CONFIG.PROTOCOL] DATA_WIDTH=[doa_inventory_value $port CONFIG.DATA_WIDTH]"
    }
    foreach port [get_bd_ports -quiet] {
        set port_name [doa_inventory_value $port NAME]
        if {[regexp -nocase {(clk|clock|reset|rst|irq|interrupt)} $port_name]} {
            doa_inventory_emit $channel "TOP_PIN $port DIR=[doa_inventory_value $port DIR] TYPE=[doa_inventory_value $port TYPE]"
        }
    }
    doa_inventory_emit $channel "=== BASE BD INVENTORY END ==="
    close $channel
}

open_work_project
set output [ensure_output_directory]
set ip_repo [file normalize [require_env IP_REPO]]
# Append (never overwrite): keep any base-project IP repositories visible.
doa_append_ip_repo_paths [list $ip_repo]
select_base_bd
doa_dump_base_bd_inventory [file join $output step08_base_bd_inventory.txt]
source [file join $script_dir create_doa_v7_hier.tcl]
if {[llength [get_bd_cells -quiet /doa_v7]]} {
    puts "Replacing existing generated hierarchy /doa_v7"
    delete_bd_objs [get_bd_cells /doa_v7]
}
set hierarchy [create_doa_v7_hier / doa_v7]
set map [file normalize [require_env ZCU208_BD_MAP]]
if {![file exists $map]} { error "ZCU208_BD_MAP not found: $map" }
source $map
set mode [expr {[info exists ::env(INTEGRATION_MODE)] ? $::env(INTEGRATION_MODE) : "mapped"}]
connect_doa_v7_to_base doa_v7 $mode
assign_bd_address
validate_bd_design
if {$mode eq "mapped"} {
    doa_post_validate_assertions
    set all_bd_cells [get_bd_cells -hier]
    set addr_spaces [lsort -unique [get_bd_addr_spaces -quiet -of_objects $all_bd_cells]]
    set addressed_segs {}
    foreach sp $addr_spaces {
        set sp_segs [get_bd_addr_segs -quiet -addressed -of_objects $sp]
        if {[llength $sp_segs] > 0} {
            set addressed_segs [concat $addressed_segs $sp_segs]
        }
    }
    set addressed_segs [lsort -unique $addressed_segs]
    set addr_fh [open [file join $output doa_address_map.txt] w]
    puts $addr_fh "=== ASSIGNED BD ADDRESS SEGMENTS (SPACES=[llength $addr_spaces] SEGS=[llength $addressed_segs]) ==="
    foreach seg $addressed_segs {
        set off [doa_inventory_value $seg OFFSET]
        set rng [doa_inventory_value $seg RANGE]
        puts $addr_fh [format "%-14s %-12s %s" $off $rng $seg]
    }
    puts $addr_fh "=== DOA SLAVE INTERFACE ADDRESS CHECK ==="
    foreach {slave_label slave_pin_path} {
        covariance           /doa_v7/covariance/s_axi_ctrl
        candidate_peak       /doa_v7/candidate_peak/s_axi_ctrl
        beam_monitor         /doa_v7/beam_monitor/s_axi_ctrl
        doa_cov_fifo         /doa_cov_fifo/S_AXI
        doa_beam_fifo        /doa_beam_fifo/S_AXI
        doa_subband_bridge_0 /doa_subband_bridge_0/s_axi_ctrl
    } {
        set spin [get_bd_intf_pins -quiet $slave_pin_path]
        if {[llength $spin] != 1} {
            close $addr_fh
            error "Missing expected DOA AXI4-Lite slave interface pin '$slave_pin_path'"
        }
        set sseg_addressed [get_bd_addr_segs -quiet -addressed -of_objects $spin]
        puts $addr_fh [format "%-22s %-38s ADDRESSED_SEGS=%s" $slave_label $slave_pin_path $sseg_addressed]
        if {[llength $sseg_addressed] == 0} {
            close $addr_fh
            error "Expected DOA AXI4-Lite slave '$slave_label' ($slave_pin_path) was not assigned an address segment (see build/output/doa_address_map.txt)"
        }
    }
    close $addr_fh
}
# save_bd_design persists the BD; Vivado has no "save_project" Tcl command
# (project-mode property changes persist to the .xpr automatically).
save_bd_design
puts "Integrated DOA V7 hierarchy into [current_bd_design] using mode=$mode"
close_project
invalidate_downstream_stamps {
    step09_vivado_validate.done
    step10_synth.done
    step11_impl.done
    step12_bitstream.done
    step13_export_xsa.done
    step15_package.done
}

