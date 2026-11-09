# Host shim for `ap_int.h` / `hls_stream.h` / `ap_axi_sdata.h`

This directory lets **the production kernel and the production C-simulation
testbench** be compiled with `g++` on a machine that has no Vitis HLS:

```bash
make host-kernel-check     # builds tb/phase_interf_4ch_tb.cpp + src/phase_interf_4ch.cpp
```

It exists because the two failure modes that cost the most time on a licensed
machine are (a) the kernel not compiling at all and (b) the AXI record being
packed differently from what the PS expects. Both are caught here for free.

## What it proves

* `src/phase_interf_4ch.cpp` compiles as C++11/14 with only the documented
  `ap_int` / `ap_uint` / `hls::stream` / `ap_axiu` surface.
* The 512-bit input beat is unpacked lane-major exactly as
  `doa_covariance_4ch_v4` does.
* The 16 accumulator words are emitted in the documented order with `TLAST` on
  word 15, and their values equal the tool-independent `pir::FrameAccumulator`
  reference for 16-sample, 4096-sample and phase-injection frames.
* The six Q3.13 phases, the frame-tag echo and the phases-valid bit land in the
  documented bit positions, and the az/el sign convention is as specified.

## What it does NOT prove

* No scheduling, initiation interval, latency, pipelining or resource data.
  `#pragma HLS` lines are ignored by g++.
* No saturation/overflow semantics of the real `ap_int` (values here stay inside
  64 bits by design and by test).
* No cycle-accurate handshake behaviour: the FIFO never applies back-pressure.
* It does not replace `csim_design` / `csynth_design` / `export_design`. Gate G2
  in `V07_PHASE_INTERFEROMETRY.md` still requires Vitis HLS 2023.2.

Scope: `ap_uint<W>` / `ap_int<W>` for `W <= 64` with arbitrary bit ranges and
`ap_uint<512>` storage, conversions, comparisons, `+ - *`, `<< >> | &`, and
bit-slice get/set.
