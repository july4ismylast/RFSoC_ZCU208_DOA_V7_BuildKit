# Stage V06 — wideband channelizer feasibility

**Status after V04/V05:** the RFDC configuration transaction is proven in
scratch (4 GSPS, Fine Real→I/Q DDC, decimation 2, MTS persisted), and
`rfdc_repack4` is accepted in Vitis HLS. V06 must now prove **one**
channelizer channel before any V07/`step08` integration is attempted.

## 1. One-channel target contract

| Item | V06 requirement |
|---|---|
| Input, one antenna channel | SSR-8 complex stream from V05 `rfdc_repack4`: 8 × `{Q[15:0], I[15:0]}` per 250 MHz cycle = 2.000 GS/s |
| Channelizer | critically sampled PFB/FFT, **1024 bands**, prototype **12 taps/band** (12,288 coefficients), production reference stopband target 100 dB |
| Output snapshot | 1024 complex bins per 1024 input samples; with SSR-8 serialized output this is 128 output beats/snapshot |
| Snapshot/bin spacing | 2.000 GHz / 1024 = **1.953125 MHz** |
| Clock gate | one channel must synthesize for `xczu48dr-fsvg1517-2-e` at **4.0 ns** with non-negative slack before x4 extrapolation is reviewed |
| Coherence gate | all four production channels must be identical instances with identical latency, scaling and bin ordering |

The existing `ip/matlab/channelizer_hdl` model/package flow is a legacy
**64-band, four-sample/cycle** harness. It is useful code to adapt, but a
successful run of that harness is **not** V06 evidence and its packaged IP
must not be used as the production channelizer.

## 2. Candidate comparison

| Candidate | Why it is considered | Main risk / adaptation | V06 order |
|---|---|---|---|
| **MathWorks `dsphdl.Channelizer`** | Already used by the repo harness and shares the `dsp.Channelizer` prototype used by the MATLAB reference. MathWorks documents power-of-two vector inputs in the 2–64 range and FFT lengths up to 2^16 for HDL, so SSR-8/1024 is inside the documented envelope: <https://www.mathworks.com/help/dsphdl/ref/dsphdl.channelizer-system-object.html> | Generated 1024-band resource/timing, output fixed-point type, latency and bin ordering are unproven on ZU48DR | **Plan A — probe first** |
| **MazinLab RFSoC_OPFB** | Real RFSoC SSR polyphase filter-bank ecosystem; pinned adapters already exist under `ip/upstream_opfb/` | Upstream FFT is fixed **16-way × 4096-point** (`ssrfft_16x4096_axis`) and the surrounding HLS/IP interfaces do not match our SSR-8/1024 contract without redesign | Plan B if Plan A fails resource/timing |
| **AMD FIR Compiler + AMD FFT, hand-assembled SSR PFB** | FIR Compiler 7.2 is already pinned; AMD IP would be native to Vivado 2023.2 | AMD FFT VLNV/version is not yet checked or pinned (required by the V00 rule); commutator, coefficient banks, scaling and SSR ordering become custom design work | Plan C |
| **Custom HLS/RTL PFB** | Maximum control over interface and scaling | No exact SSR-8/1024 implementation exists in the audited repos; highest verification and timing-closure risk | Last resort |

The other audited upstream projects (RFSoC-MTS, PYNQ, SAM, SPEAR) are RFDC,
clocking or beamforming references; none supplies a suitable 1024-band
SSR-8 PFB channelizer for this stage.

## 3. V06 gates

### Gate 0 — MATLAB API/vector probe (current gate)

Run exactly:

```bash
make -C ip/matlab/channelizer_hdl probe
```

This executes `v06_probe_ssr8_1024.m`. It must prove, in the installed
MATLAB/DSP HDL release and without generating HDL:

- the 1024-band × 12-tap/band prototype has 12,288 coefficients;
- `dsphdl.Channelizer` constructs with those coefficients;
- fixed-point `fi(...,1,16,15)` complex data is accepted as 8×1 vectors;
- `OutputSize='Same as input size'` returns 8×1 data;
- `getLatency` (if available), measured first-valid cycle, output type and
  valid-beat count are recorded;
- one deterministic tone produces a dominant channel in the first
  collected 1024-output snapshot.

Expected final line in `build/output/v06_channelizer_probe.rpt`:

```text
V06 CHANNELIZER PROBE RESULT=PASS
```

A Gate-0 PASS proves only the MATLAB object/configuration path. It does
**not** prove HDL generation, FPGA resources, timing, AXI4-Stream
packaging, exact bin order, or numerical equivalence to the reference.

If the probe fails, stop. Do not run `make hdl`, `make package`,
`step05_channelizer`, `step06_collect_ip`, or `step08`; return the full
probe report for diagnosis.

### Gate 1 — parameterize the Simulink/HDL harness

Adapt the legacy harness from 64 bands/4 lanes to the `config.mk`
values (1024 bands/8 lanes), generate Verilog for one channel, and record
the generated top, port list, output type, latency and HDL Coder reports.
Do not package it as production IP until an explicit AXI4-Stream wrapper
contract (TDATA packing, TVALID/TREADY behaviour, bin index/time order)
is written.

### Gate 2 — one-channel Vivado OOC synthesis

Synthesize one channel out-of-context for the pinned part at 4.0 ns.
Acceptance requires the utilization (LUT/FF/DSP/BRAM/URAM) and WNS/TNS
reports, followed by an explicit x4 extrapolation review including the
V03 MTS base, V05 gearbox, search/DOA logic and routing margin.

### Gate 3 — numerical ordering and phase

Compare the HDL-oriented object/RTL against the floating-point
`dsp.Channelizer` reference after latency alignment. Freeze:

- output scalar order over the 128 SSR-8 beats of one snapshot;
- bin index → baseband/RF frequency mapping;
- scaling, saturation/rounding and output word length;
- common per-bin phase rotation (acceptable for cross-channel DOA only
  if bit-identical across all four channels).

Only after Gates 0–3 pass is Plan A selected for V07. If Gate 1 or 2
fails, the same gates are applied to the MazinLab OPFB Plan B before any
production BD work resumes.
