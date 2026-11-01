# First-draft audit and V7 update comparison

## Conclusion

The attached first draft was a sensible research scaffold, but it was not yet a
plausible deployable ZCU208 design. It contained two small scalar HLS examples,
a scalar MATLAB channelizer template, upstream repository adapters, and a
minimal PS/reset block design. Its own Tcl explicitly did not configure RFDC or
MTS, and `all` stopped after fetching/building IP rather than producing a routed
bitstream.

This revision retains the useful source matrix/adapters and replaces the unsafe
or incomplete parts with a V7-specific, checkpointed ZCU208 flow.

## Direct comparison

| Area | Attached first draft | This V7/ZCU208 revision |
|---|---|---|
| Target | XCZU48DR part variable, no verified shell requirement | Exact XCZU48DR plus mandatory verified ZCU208 `BASE_XPR` |
| RFDC/MTS | Minimal PS/reset shell; RFDC/MTS deliberately absent | Preserves and copies a proven ZCU208 RFDC/MTS base; no guessed settings |
| Sample throughput | Spectrum/beam accepted one sample per channel per beat | All sample cores accept 4 lanes × 4 channels in AXI512 at II=1 |
| DOA sufficient statistic | Missing | V7 calibrated six-baseline covariance, 4096 snapshots, exact C test |
| Detection | Power only | Four-lane power plus frame peak/average candidate gate |
| Search/capture coupling | Not defined | Independent search, capture, and beam inputs; output FIFOs |
| MATLAB reference | Scalar channelizer template only | Complete embedded V7 simulation, estimator, realism, calibration, and HIL |
| HDL generation | One MATLAB path | Selectable HDL Coder, Model Composer, OPFB, or external packaged IP |
| Vivado flow | Catalog/minimal-shell helpers | Base copy → integrate → validate → synth → route/timing → bit → XSA |
| Failure recovery | Broad `all` and `clean` targets | One stamp/log/product set per named stage; force/clean/dry-run/status |
| HIL | Missing | AXI512 stimulus, exact 16-word covariance, angle comparison metadata |
| Documentation | README and source matrix | Architecture JPEG, stage guide, algorithm guide, file/code guide, references |

## What is plausible now

- The PL/PS boundary matches the V7 workload: high-rate accumulation in PL,
  low-rate nonlinear refinement/tracking on the processor.
- Stream widths are consistent across authored HLS blocks.
- The covariance result is small enough for deterministic FIFO/DMA transfer.
- A failed IP, integration, synthesis, or route stage is independently
  reproducible and logged.
- Native ZCU208 RFDC/MTS configuration is treated as a prerequisite, not
  inferred from a different board.

## What still requires the user's board and licensed tools

- select/build the exact ZCU208 base project and fill its BD pin names;
- generate the selected channelizer IP in a release compatible with the base;
- run HLS C simulation/synthesis and inspect latency/resources;
- close Vivado timing and inspect utilization;
- implement/profile the V7 estimator in the selected R5 software environment;
- program CLK104/RFDC, run repeated MTS, and measure alignment;
- perform exact HIL, RF loopback, calibration, thermal, and chamber/field tests.

Therefore the design is implementable and substantially more plausible, but
neither “fits” nor “0.1° on real hardware” should be asserted before those
reports and measurements exist.

