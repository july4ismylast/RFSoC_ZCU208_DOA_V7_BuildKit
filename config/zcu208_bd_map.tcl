# This file is the only board/base-project-specific integration layer.
# Replace the mapped-mode error with connections to the verified RFDC/MTS base.
# The three input streams MUST be independently buffered or branched upstream:
# a stalled 4096-sample DOA capture must never backpressure the search channelizer.

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
    error {Production map not filled in. Edit config/zcu208_bd_map.tcl to connect:
  S_AXIS_SEARCH       <- continuous RFDC/DDC/channelizer stream
  S_AXIS_DOA_CAPTURE  <- candidate-triggered 4096-sample capture FIFO
  S_AXIS_BEAM_MONITOR <- optional independently buffered diagnostic stream
  M_AXIS_CANDIDATE    -> candidate FIFO/interrupt (bin, valid, peak, average)
  M_AXIS_COVARIANCE   -> AXI DMA/FIFO to R5/A53 (16 signed int64 words)
  S_AXI_*_CTRL        <- PS AXI master through SmartConnect
  aclk/aresetn        <- the verified stream clock/reset domain
Then call assign_bd_address for both control slaves. For a wiring-only test use INTEGRATION_MODE=external_ports.}
}
